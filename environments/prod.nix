{
  networking.hostName = "xos-assistant-prod";

  # OPERATOR: every value below must be decided before the community bot is
  # invited anywhere. The placeholders are safe — an operator id of "0"
  # matches no account, so the assistant refuses every group add until the
  # real id is set. The bot token and the model API key are never in this
  # repository: the operator-secrets collector asks for them at first boot.

  # The numeric Telegram user id of the account whose group invitations the
  # assistant accepts.
  custom.assistant.telegramOperator = "11814515";

  # The published privacy policy address the /privacy command answers with.
  # Until it exists, leave this commented and the bot answers its fixed
  # not-yet-published line.
  custom.assistant.privacyPolicy =
    "https://git.halogenos.org/halogenOS/legal/src/branch/main/bot-assistant-privacy-policy.md";

  # The group's moderation bot, once the report flow is wanted in prod.
  custom.assistant.moderationHandle = "MissRose_bot";

  # Direct chats stay off until their feature set ships.
  #custom.assistant.directChats = "on";
}
