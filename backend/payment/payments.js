/**
 * Payment Routes (Stripe Integration)
 * 
 * Handles:
 * - Creating Stripe checkout sessions
 * - Managing customer portal
 * - Webhook events from Stripe
 * - Subscription status sync
 * 
 * Security:
 * - Pro-Free accounts protected from downgrade
 * - Webhook signature verification
 */

const express = require('express');
const Stripe = require('stripe');
const SubscriptionService = require('../core/services/subscription-service');

function createPaymentRoutes(db) {
    const router = express.Router();
    const stripe = Stripe(process.env.STRIPE_SECRET_KEY);
    const subscriptionService = new SubscriptionService(db);

    const YOUR_DOMAIN = process.env.APP_URL || 'http://localhost:8080';
    const PRICE_ID = process.env.STRIPE_PRICE_ID;

    /**
     * POST /create-checkout-session
     * Create Stripe checkout session for Pro subscription
     */
    router.post('/create-checkout-session', async (req, res) => {
        try {
            const { companyId, successUrl, cancelUrl } = req.body;

            if (!companyId) {
                return res.status(400).json({ error: 'Missing companyId' });
            }

            // Check if company is Pro-Free (they shouldn't be able to upgrade)
            const planDetails = await subscriptionService.getCompanyPlan(companyId);

            if (planDetails.isProFree) {
                return res.status(400).json({
                    error: 'Pro-Free accounts cannot purchase subscriptions'
                });
            }

            const session = await stripe.checkout.sessions.create({
                mode: 'subscription',
                payment_method_types: ['card'],
                client_reference_id: companyId,
                metadata: {
                    companyId: companyId
                },
                line_items: [
                    {
                        price: PRICE_ID,
                        quantity: 1,
                    },
                ],
                success_url: successUrl || `${YOUR_DOMAIN}/payment/success?session_id={CHECKOUT_SESSION_ID}`,
                cancel_url: cancelUrl || `${YOUR_DOMAIN}/payment/cancel`,
            });

            res.json({ url: session.url });

        } catch (error) {
            console.error('[Payment] Checkout error:', error);
            res.status(500).json({ error: error.message });
        }
    });

    /**
     * POST /create-portal-session
     * Create Stripe customer portal session
     */
    router.post('/create-portal-session', async (req, res) => {
        try {
            const { companyId, returnUrl } = req.body;

            if (!companyId) {
                return res.status(400).json({ error: 'Missing companyId' });
            }

            const companyDoc = await db.collection('companies').doc(companyId).get();

            if (!companyDoc.exists) {
                return res.status(404).json({ error: 'Company not found' });
            }

            const customerId = companyDoc.data().stripeCustomerId;

            if (!customerId) {
                return res.status(400).json({
                    error: 'No active subscription or customer record found'
                });
            }

            const session = await stripe.billingPortal.sessions.create({
                customer: customerId,
                return_url: returnUrl || `${YOUR_DOMAIN}/plans`,
            });

            res.json({ url: session.url });

        } catch (error) {
            console.error('[Payment] Portal error:', error);
            res.status(500).json({ error: error.message });
        }
    });

    /**
     * POST /webhook
     * Handle Stripe webhook events
     * CRITICAL: Pro-Free accounts must not be downgraded
     */
    router.post('/webhook', express.raw({ type: 'application/json' }), async (req, res) => {
        const sig = req.headers['stripe-signature'];
        let event;

        try {
            event = stripe.webhooks.constructEvent(
                req.body,
                sig,
                process.env.STRIPE_WEBHOOK_SECRET
            );
        } catch (err) {
            console.error(`[Payment] Webhook signature verification failed:`, err.message);
            return res.status(400).send(`Webhook Error: ${err.message}`);
        }

        // Handle the event
        switch (event.type) {
            case 'checkout.session.completed':
                const session = event.data.object;
                const companyId = session.client_reference_id || session.metadata?.companyId;

                if (companyId) {
                    console.log(`✅ [Payment] Checkout completed for company: ${companyId}`);

                    await subscriptionService.upgradeToPro(
                        companyId,
                        session.customer,
                        session.subscription
                    );
                }
                break;

            case 'customer.subscription.updated':
                const updatedSubscription = event.data.object;

                const updateSnapshot = await db.collection('companies')
                    .where('stripeCustomerId', '==', updatedSubscription.customer)
                    .get();

                if (!updateSnapshot.empty) {
                    const companyData = updateSnapshot.docs[0].data();
                    const companyDocId = updateSnapshot.docs[0].id;

                    // 🔐 CRITICAL: Don't modify Pro-Free accounts
                    if (companyData.isProFree === true) {
                        console.log(`⚠️ [Payment] Ignoring subscription update for Pro-Free company: ${companyDocId}`);
                        break;
                    }

                    const status = updatedSubscription.status;

                    if (status === 'active' || status === 'trialing') {
                        await db.collection('companies').doc(companyDocId).update({
                            subscriptionStatus: status,
                            plan: 'pro',
                            isFree: false,
                            updatedAt: new Date()
                        });
                    } else if (status === 'past_due' || status === 'unpaid') {
                        console.warn(`⚠️ [Payment] Subscription ${status} for ${companyDocId}`);
                        // You may want to send an email here
                    }
                }
                break;

            case 'customer.subscription.deleted':
                const deletedSubscription = event.data.object;

                const deleteSnapshot = await db.collection('companies')
                    .where('stripeCustomerId', '==', deletedSubscription.customer)
                    .get();

                if (!deleteSnapshot.empty) {
                    const companyData = deleteSnapshot.docs[0].data();
                    const companyDocId = deleteSnapshot.docs[0].id;

                    // 🔐 CRITICAL: Don't downgrade Pro-Free accounts
                    if (companyData.isProFree === true) {
                        console.log(`⚠️ [Payment] Ignoring subscription deletion for Pro-Free company: ${companyDocId}`);
                        break;
                    }

                    await subscriptionService.downgradeToFree(companyDocId);
                }
                break;

            default:
                console.log(`[Payment] Unhandled event type: ${event.type}`);
        }

        res.json({ received: true });
    });

    /**
     * GET /success
     * Payment success page
     */
    router.get('/success', async (req, res) => {
        const sessionId = req.query.session_id;

        if (sessionId) {
            try {
                const session = await stripe.checkout.sessions.retrieve(sessionId);

                if (session.payment_status === 'paid') {
                    const companyId = session.client_reference_id || session.metadata?.companyId;

                    if (companyId) {
                        console.log(`[Payment] Force-updating company ${companyId} from success page`);

                        await subscriptionService.upgradeToPro(
                            companyId,
                            session.customer,
                            session.subscription
                        );
                    }
                }
            } catch (e) {
                console.error('[Payment] Error verifying session on success page:', e);
            }
        }

        res.send(`
            <html>
                <head>
                    <title>Payment Successful</title>
                    <style>
                        body {
                            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            height: 100vh;
                            margin: 0;
                            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                        }
                        .card {
                            background: white;
                            padding: 48px;
                            border-radius: 16px;
                            text-align: center;
                            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
                            max-width: 400px;
                        }
                        .icon {
                            font-size: 64px;
                            margin-bottom: 16px;
                        }
                        h1 {
                            color: #10b981;
                            margin: 0 0 16px 0;
                            font-size: 28px;
                        }
                        p {
                            color: #666;
                            margin: 0 0 24px 0;
                        }
                        .button {
                            display: inline-block;
                            padding: 12px 32px;
                            background: #6366F1;
                            color: white;
                            text-decoration: none;
                            border-radius: 8px;
                            font-weight: 600;
                        }
                    </style>
                </head>
                <body>
                    <div class="card">
                        <div class="icon">✓</div>
                        <h1>Payment Successful!</h1>
                        <p>Your subscription has been activated. Welcome to Pro!</p>
                        <a href="${YOUR_DOMAIN}" class="button">Return to App</a>
                    </div>
                </body>
            </html>
        `);
    });

    /**
     * GET /cancel
     * Payment canceled page
     */
    router.get('/cancel', (req, res) => {
        res.send(`
            <html>
                <head>
                    <title>Payment Canceled</title>
                    <style>
                        body {
                            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            height: 100vh;
                            margin: 0;
                            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                        }
                        .card {
                            background: white;
                            padding: 48px;
                            border-radius: 16px;
                            text-align: center;
                            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
                            max-width: 400px;
                        }
                        .icon {
                            font-size: 64px;
                            margin-bottom: 16px;
                        }
                        h1 {
                            color: #ef4444;
                            margin: 0 0 16px 0;
                            font-size: 28px;
                        }
                        p {
                            color: #666;
                            margin: 0 0 24px 0;
                        }
                        .button {
                            display: inline-block;
                            padding: 12px 32px;
                            background: #6366F1;
                            color: white;
                            text-decoration: none;
                            border-radius: 8px;
                            font-weight: 600;
                        }
                    </style>
                </head>
                <body>
                    <div class="card">
                        <div class="icon">✕</div>
                        <h1>Payment Canceled</h1>
                        <p>Your payment was canceled. No charges were made.</p>
                        <a href="${YOUR_DOMAIN}" class="button">Return to App</a>
                    </div>
                </body>
            </html>
        `);
    });

    /**
     * POST /sync-subscription
     * Manually sync subscription status (useful for localhost testing)
     */
    router.post('/sync-subscription', async (req, res) => {
        try {
            const { companyId } = req.body;

            if (!companyId) {
                return res.status(400).json({ error: 'Missing companyId' });
            }

            const companyDoc = await db.collection('companies').doc(companyId).get();

            if (!companyDoc.exists) {
                return res.status(404).json({ error: 'Company not found' });
            }

            const customerId = companyDoc.data().stripeCustomerId;

            if (!customerId) {
                return res.json({ status: 'no_customer', isFree: true });
            }

            const subscriptions = await stripe.subscriptions.list({
                customer: customerId,
                limit: 1,
                status: 'all'
            });

            if (subscriptions.data.length === 0) {
                await subscriptionService.downgradeToFree(companyId);
                return res.json({ status: 'none', isFree: true });
            }

            const subscription = subscriptions.data[0];
            const status = subscription.status;

            if (status === 'active' || status === 'trialing') {
                await subscriptionService.upgradeToPro(
                    companyId,
                    customerId,
                    subscription.id
                );
                return res.json({ status, isFree: false });
            } else {
                await subscriptionService.downgradeToFree(companyId);
                return res.json({ status, isFree: true });
            }

        } catch (error) {
            console.error('[Payment] Sync error:', error);
            res.status(500).json({ error: error.message });
        }
    });

    return router;
}

module.exports = createPaymentRoutes;