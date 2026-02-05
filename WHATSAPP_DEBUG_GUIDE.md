# WhatsApp Integration - Debugging & Testing Guide

## Recent Fixes (2026-02-05)

### Frontend Improvements
1. **Better Error Handling**
   - Added proper response parsing for connect() method
   - Display error messages in red boxes
   - Show detailed status messages
   - Added loading state for QR code generation

2. **Enhanced Status Display**
   - Show `statusMessage` from backend
   - Display error and disconnect reasons
   - Better visual feedback for all states

3. **QR Code Display**
   - Added fallback loading indicator
   - Proper null checking
   - Debug logging for troubleshooting

4. **Service Layer**
   - Complete rewrite with better error handling
   - Proper response format parsing
   - Clear cache on disconnect
   - Better timeout handling

### Backend Improvements
1. **Session Manager**
   - Heartbeat monitoring every 60 seconds
   - Exponential backoff reconnection
   - Proper auth data management
   - Better state transitions

## Testing Steps

### 1. Test Connection Flow

```bash
# Terminal 1: Backend
cd /Users/meesam/projects/urbox.ai/backend
node server.js

# Terminal 2: Frontend
cd /Users/meesam/projects/urbox.ai/frontend
flutter run -d web-server

# Terminal 3: Test API
curl -X GET "http://localhost:3004/health"
```

### 2. Test WhatsApp Connection

**Step-by-step:**

1. **Navigate to WhatsApp Tab**
   - Open the app in browser
   - Go to WhatsApp section

2. **Click "Connect WhatsApp"**
   - Watch browser console for logs:
     ```
     [WhatsApp] Status is qr_pending, fetching QR code...
     [WhatsApp] QR code received: YES (XXX chars)
     [WhatsApp] QR code set in state
     ```

3. **Check Backend Logs**
   - Should see:
     ```
     [WhatsApp] Starting session for user {userId}
     [WhatsApp] QR code generated for user {userId}
     ```

4. **Verify QR Code Display**
   - Should show actual QR code (black and white squares)
   - If showing "Generating QR code..." for more than 10 seconds, check logs

5. **Scan QR Code**
   - Open WhatsApp on phone
   - Go to Settings > Linked Devices > Link a Device
   - Scan the QR code

6. **Verify Connection**
   - Status should change to "Connected"
   - Should show phone number and name
   - Backend should log: `[WhatsApp] Client ready for {userId}`

### 3. Test API Endpoints Directly

```bash
# Get status
curl -X GET "http://localhost:3004/api/whatsapp/status?userId=YOUR_USER_ID"

# Expected response:
{
  "success": true,
  "data": {
    "status": "disconnected" | "qr_pending" | "connected",
    "phone": "1234567890",
    "name": "User Name",
    "qrCode": "...",
    "connectedAt": "2026-02-05T...",
    "lastSync": "2026-02-05T..."
  }
}

# Get QR code (when status is qr_pending)
curl -X GET "http://localhost:3004/api/whatsapp/qr?userId=YOUR_USER_ID"

# Expected response:
{
  "success": true,
  "qrCode": "2@..."
}

# Start connection
curl -X POST "http://localhost:3004/api/whatsapp/connect" \
  -H "Content-Type: application/json" \
  -d '{"userId":"YOUR_USER_ID","companyId":"YOUR_COMPANY_ID"}'

# Expected response:
{
  "success": true
}
```

## Common Issues & Solutions

### Issue 1: QR Code Shows "Generating..." Forever

**Symptoms:**
- Status is "qr_pending"
- QR code never appears
- Console shows: `[WhatsApp] QR code received: NULL`

**Debugging:**
```bash
# Check backend logs
# Look for:
[WhatsApp] QR code generated for user {userId}

# Check Firestore
# Collection: whatsappSessions
# Document: {userId}
# Should have: qrCode field with long string starting with "2@"

# Test QR endpoint directly
curl -X GET "http://localhost:3004/api/whatsapp/qr?userId=YOUR_USER_ID"
```

**Solutions:**
1. **QR not generated yet**: Wait 5-10 seconds, it takes time
2. **Session stuck**: Disconnect and reconnect
3. **Auth data exists**: Delete `.wwebjs_auth/session-{userId}` folder
4. **Puppeteer issue**: Check backend logs for Puppeteer errors

### Issue 2: Connection Fails Immediately

**Symptoms:**
- Status goes to "error"
- Error message displayed
- Backend shows auth failure

**Debugging:**
```bash
# Check backend logs for:
[WhatsApp] Auth failure for user {userId}:

# Check if auth directory exists
ls -la backend/.wwebjs_auth/

# Check Firestore
# Look for error field in whatsappSessions/{userId}
```

**Solutions:**
1. **Delete auth data**: `rm -rf backend/.wwebjs_auth/session-{userId}`
2. **Check Puppeteer**: Ensure Chrome/Chromium is installed
3. **Check permissions**: Ensure backend has write access to `.wwebjs_auth`

### Issue 3: Disconnects Frequently

**Symptoms:**
- Connects successfully
- Disconnects after a few minutes
- Reconnection attempts fail

**Debugging:**
```bash
# Check heartbeat logs
[WhatsApp] Heartbeat for {userId}: CONNECTED

# Check for errors
[WhatsApp] Heartbeat error for {userId}: ...

# Check Firestore lastHeartbeat
# Should update every 60 seconds
```

**Solutions:**
1. **Network issues**: Check internet connection
2. **Server resources**: Check CPU/memory usage
3. **WhatsApp limits**: Don't connect too many devices
4. **Session conflict**: Only one session per phone number

### Issue 4: Messages Not Appearing

**Symptoms:**
- Connected successfully
- Groups monitored
- No messages showing

**Debugging:**
```bash
# Check if group is monitored
curl -X GET "http://localhost:3004/api/whatsapp/monitored?userId=YOUR_USER_ID"

# Check messages collection
# Firestore: whatsappMessages
# Filter by userId and groupId

# Check backend logs
[WhatsApp] New message in monitored group {groupName} for user {userId}
```

**Solutions:**
1. **Group not monitored**: Re-add group to monitoring
2. **No new messages**: Send a test message in the group
3. **CompanyId mismatch**: Check user's companyId matches
4. **Firestore rules**: Ensure write permissions

## Debug Checklist

### Frontend
- [ ] Browser console shows no errors
- [ ] Status updates every 2 seconds during connection
- [ ] QR code appears within 10 seconds
- [ ] Error messages are displayed clearly
- [ ] Status message shows correct information

### Backend
- [ ] Server starts without errors
- [ ] WhatsApp session manager initializes
- [ ] QR code generates successfully
- [ ] Client connects and shows "ready"
- [ ] Heartbeat logs appear every 60 seconds
- [ ] Messages are saved to Firestore

### Firestore
- [ ] `whatsappSessions/{userId}` document exists
- [ ] Status field is correct
- [ ] QR code field exists when status is "qr_pending"
- [ ] Phone and name fields exist when connected
- [ ] `lastHeartbeat` updates regularly

### File System
- [ ] `.wwebjs_auth` directory exists
- [ ] `session-{userId}` subdirectory created after auth
- [ ] Directory has proper permissions

## Performance Monitoring

### Key Metrics
- **QR Generation Time**: Should be < 10 seconds
- **Connection Time**: Should be < 5 seconds after QR scan
- **Heartbeat Interval**: Exactly 60 seconds
- **Message Processing**: < 1 second per message

### Monitoring Commands
```bash
# Watch backend logs
tail -f backend/logs/app.log

# Monitor Firestore writes
# Firebase Console > Firestore > Usage tab

# Check memory usage
ps aux | grep node

# Check active sessions
curl http://localhost:3004/health
```

## Troubleshooting Commands

```bash
# Restart backend
cd backend
pkill -f "node server.js"
node server.js

# Clear all WhatsApp sessions
rm -rf backend/.wwebjs_auth/*

# Clear Firestore cache (frontend)
# In browser console:
localStorage.clear()
sessionStorage.clear()

# Reset Flutter app
cd frontend
flutter clean
flutter pub get
flutter run -d web-server

# Check Puppeteer installation
cd backend
npm list puppeteer

# Test Firestore connection
curl http://localhost:3004/health
```

## Success Indicators

### ✅ Everything Working
- Status: "Connected"
- Phone number and name displayed
- QR code appeared within 10 seconds
- No error messages
- Heartbeat logs every 60 seconds
- Messages appear in real-time
- Groups can be monitored/unmonitored
- Reconnects automatically on disconnect

### ❌ Something Wrong
- Status stuck on "Initializing" for > 30 seconds
- QR code never appears
- Error messages displayed
- Backend logs show errors
- Heartbeat stops
- Messages don't appear
- Can't monitor groups

## Next Steps

If issues persist after following this guide:

1. **Check Dependencies**
   ```bash
   cd backend
   npm install
   
   cd frontend
   flutter pub get
   ```

2. **Update Packages**
   ```bash
   cd backend
   npm update whatsapp-web.js puppeteer
   ```

3. **Check Firestore Rules**
   - Ensure read/write permissions for authenticated users

4. **Review Logs**
   - Backend: Check console output
   - Frontend: Check browser console
   - Firestore: Check Firebase Console

5. **Contact Support**
   - Provide backend logs
   - Provide browser console logs
   - Provide steps to reproduce
