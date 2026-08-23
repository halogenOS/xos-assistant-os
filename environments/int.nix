{
  networking.hostName = "xos-assistant-int";

  # int runs against a throwaway test bot, not the community one. The
  # operator id "0" matches no real account, so until the real value is set
  # the assistant refuses every group add — the safe direction. Set it to
  # the operating account's numeric Telegram user id before inviting the
  # bot anywhere. The bot token itself is never configuration: the
  # operator-secrets collector asks for it at first boot.
  custom.assistant.telegramOperator = "0";

  # Left at their defaults on int: no privacy policy address is published
  # for the test deployment (the bot answers its fixed line), no moderation
  # bot rides along (the report tool stays unregistered), and direct chats
  # stay off.
  #custom.assistant.privacyPolicy = "https://halogenos.org/privacy";
  #custom.assistant.moderationHandle = "<the test group's moderation bot>";
  #custom.assistant.directChats = "on";

  # int-only: drop to sulogin on emergency instead of hanging
  boot.kernelParams = [ "systemd.setenv=SYSTEMD_SULOGIN_FORCE=1" ];
}
