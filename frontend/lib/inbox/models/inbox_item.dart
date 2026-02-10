import '../../whatsapp/models/whatsapp_model.dart';
import '../../slack/models/slack_message.dart';
import 'email_model.dart';

enum InboxItemType { email, whatsapp, slack }

abstract class InboxItem {
  String get id;
  DateTime get date;
  String
  get title; // Top line (Subject for email, Group Name for WhatsApp, Channel for Slack)
  String
  get subtitle; // Second line (Sender for email, Sender Name for WhatsApp, etc)
  String get snippet; // Preview text
  bool get isRead;
  InboxItemType get type;

  // Original objects
  Email? get email => null;
  WhatsAppMessage? get whatsappMessage => null;
  SlackMessage? get slackMessage => null;
}

class EmailInboxItem implements InboxItem {
  final Email _email;

  EmailInboxItem(this._email);

  @override
  String get id => _email.id;

  @override
  DateTime get date => _email.date;

  @override
  String get title => _email.from.isEmpty ? '(No Sender)' : _email.from;

  @override
  String get subtitle =>
      _email.subject.isEmpty ? '(No Subject)' : _email.subject;

  @override
  String get snippet => _email.snippet;

  @override
  bool get isRead => _email.isRead;

  @override
  InboxItemType get type => InboxItemType.email;

  @override
  Email? get email => _email;

  @override
  WhatsAppMessage? get whatsappMessage => null;

  @override
  SlackMessage? get slackMessage => null;
}

class WhatsAppInboxItem implements InboxItem {
  final WhatsAppMessage _message;

  WhatsAppInboxItem(this._message);

  @override
  String get id => _message.id;

  @override
  DateTime get date => _message.timestamp;

  @override
  String get title => _message.groupName;

  @override
  String get subtitle => '${_message.senderName}: ';

  @override
  String get snippet => _message.hasMedia
      ? '[Media: ${_message.mediaType?.split('/').first ?? 'file'}]'
      : _message.body; // Changed from content to body to match urbox.ai model

  @override
  bool get isRead => true;

  @override
  InboxItemType get type => InboxItemType.whatsapp;

  @override
  WhatsAppMessage? get whatsappMessage => _message;

  @override
  Email? get email => null;

  @override
  SlackMessage? get slackMessage => null;
}

class SlackInboxItem implements InboxItem {
  final SlackMessage _message;

  SlackInboxItem(this._message);

  @override
  String get id => _message.id;

  @override
  DateTime get date => _message.timestamp;

  @override
  String get title => '#${_message.channelName}';

  @override
  String get subtitle => '${_message.senderName}: ';

  @override
  String get snippet => _message.hasMedia ? '[Media included]' : _message.body;

  @override
  bool get isRead => true; // Slack messages are implicitly read? Or need read state?

  @override
  InboxItemType get type => InboxItemType.slack;

  @override
  SlackMessage? get slackMessage => _message;

  @override
  WhatsAppMessage? get whatsappMessage => null;

  @override
  Email? get email => null;
}
