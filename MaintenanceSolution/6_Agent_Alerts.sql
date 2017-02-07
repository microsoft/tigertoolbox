USE [msdb]
GO

-- Set here the Operator name to receive notifications
DECLARE @customoper sysname
SET @customoper = 'SQLAdmins'

IF EXISTS (SELECT name FROM msdb.dbo.sysoperators WHERE name = @customoper)
BEGIN
	IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Agent Alerts Sev 10' AND category_class=2)
	BEGIN
	EXEC msdb.dbo.sp_add_category @class=N'ALERT', @type=N'NONE', @name=N'Agent Alerts Sev 10'
	END

	----------------------------------------
		
	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 825')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 825'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 825)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 825', 
			@message_id=825, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 10'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 825', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 833')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 833'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 833)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 833', 
			@message_id=833, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 10'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 833', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 855')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 855'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 855)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 855', 
			@message_id=855, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 10'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 855', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 856')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 856'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 856)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 856', 
			@message_id=856, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 10'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 856', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 3452')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 3452'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 3452)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 3452', 
			@message_id=3452, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 10'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 3452', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 3619')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 3619'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 3619)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 3619', 
			@message_id=3619, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 10'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 3619', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 17179')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 17179'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 17179)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 17179', 
			@message_id=17179, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 10'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 17179', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 17883')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 17883'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 17883)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 17883', 
			@message_id=17883, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 10'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 17883', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 17884')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 17884'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 17884)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 17884', 
			@message_id=17884, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 10'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 17884', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 17887')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 17887'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 17887)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 17887', 
			@message_id=17887, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 10'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 17887', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 17888')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 17888'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 17888)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 17888', 
			@message_id=17888, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 10'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 17888', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 17890')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 17890'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 17890)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 17890', 
			@message_id=17890, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 10'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 17890', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 28036')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 28036'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 28036)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 28036', 
			@message_id=28036, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 10'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 28036', @operator_name=@customoper, @notification_method = 1
	END

	----------------------------------------

	IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Agent Alerts Sev 16' AND category_class=2)
	BEGIN
	EXEC msdb.dbo.sp_add_category @class=N'ALERT', @type=N'NONE', @name=N'Agent Alerts Sev 16'
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 2508')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 2508'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 2508)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 2508', 
			@message_id=2508, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 16'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 2508', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 2511')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 2511'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 2511)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 2511', 
			@message_id=2511, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 16'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 2511', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 3271')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 3271'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 3271)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 3271', 
			@message_id=3271, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 16'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 3271', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 5228')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 5228'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 5228)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 5228', 
			@message_id=5228, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 16'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 5228', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 5229')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 5229'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 5229)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 5229', 
			@message_id=5229, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 16'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 5229', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 5242')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 5242'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 5242)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 5242', 
			@message_id=5242, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 16'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 5242', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 5243')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 5243'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 5243)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 5243', 
			@message_id=5243, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 16'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 5243', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 5250')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 5250'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 5250)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 5250', 
			@message_id=5250, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 16'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 5250', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 5901')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 5901'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 5901)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 5901', 
			@message_id=5901, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 16'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 5901', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 17130')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 17130'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 17130)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 17130', 
			@message_id=17130, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 16'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 17130', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 17300')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 17300'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 17300)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 17300', 
			@message_id=17300, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 16'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 17300', @operator_name=@customoper, @notification_method = 1
	END

	----------------------------------------

	IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Agent Alerts Sev 17' AND category_class=2)
	BEGIN
	EXEC msdb.dbo.sp_add_category @class=N'ALERT', @type=N'NONE', @name=N'Agent Alerts Sev 17'
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 802')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 802'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 802)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 802', 
			@message_id=802, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 17'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 802', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 845')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 845'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 845)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 845', 
			@message_id=845, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 17'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 845', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 1101')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 1101'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 1101)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 1101', 
			@message_id=1101, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 17'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 1101', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 1105')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 1105'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 1105)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 1105', 
			@message_id=1105, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 17'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 1105', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 1121')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 1121'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 1121)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 1121', 
			@message_id=1121, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 17'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 1121', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 1214')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 1214'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 1214)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 1214', 
			@message_id=1214, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 17'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 1214', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 9002')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 9002'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 9002)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 9002', 
			@message_id=9002, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 17'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 9002', @operator_name=@customoper, @notification_method = 1
	END

	----------------------------------------

	IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Agent Alerts Sev 19' AND category_class=2)
	BEGIN
	EXEC msdb.dbo.sp_add_category @class=N'ALERT', @type=N'NONE', @name=N'Agent Alerts Sev 19'
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 701')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 701'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 701)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 701', 
			@message_id=701, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 19'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 701', @operator_name=@customoper, @notification_method = 1
	END

	----------------------------------------

	IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Agent Alerts Sev 20' AND category_class=2)
	BEGIN
	EXEC msdb.dbo.sp_add_category @class=N'ALERT', @type=N'NONE', @name=N'Agent Alerts Sev 20'
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 3624')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 3624'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 3624)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 3624', 
			@message_id=3624, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 20'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 3624', @operator_name=@customoper, @notification_method = 1
	END

	----------------------------------------

	IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Agent Alerts Sev 21' AND category_class=2)
	BEGIN
	EXEC msdb.dbo.sp_add_category @class=N'ALERT', @type=N'NONE', @name=N'Agent Alerts Sev 21'
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 605')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 605'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 605)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 605', 
			@message_id=605, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 21'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 605', @operator_name=@customoper, @notification_method = 1
	END

	----------------------------------------

	IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Agent Alerts Sev 22' AND category_class=2)
	BEGIN
	EXEC msdb.dbo.sp_add_category @class=N'ALERT', @type=N'NONE', @name=N'Agent Alerts Sev 22'
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 5180')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 5180'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 5180)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 5180', 
			@message_id=5180, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 22'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 5180', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 8966')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 8966'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 8966)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 8966', 
			@message_id=8966, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 22'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 8966', @operator_name=@customoper, @notification_method = 1
	END

	----------------------------------------

	IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Agent Alerts Sev 23' AND category_class=2)
	BEGIN
	EXEC msdb.dbo.sp_add_category @class=N'ALERT', @type=N'NONE', @name=N'Agent Alerts Sev 23'
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 5572')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 5572'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 5572)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 5572', 
			@message_id=5572, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 23'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 5572', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 9100')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 9100'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 9100)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 9100', 
			@message_id=9100, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 23'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 9100', @operator_name=@customoper, @notification_method = 1
	END

	----------------------------------------

	IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Agent Alerts Sev 24' AND category_class=2)
	BEGIN
	EXEC msdb.dbo.sp_add_category @class=N'ALERT', @type=N'NONE', @name=N'Agent Alerts Sev 24'
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 823')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 823'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 823)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 823', 
			@message_id=823, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 24'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 823', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 824')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 824'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 824)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 824', 
			@message_id=824, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 24'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 824', @operator_name=@customoper, @notification_method = 1
	END

	IF EXISTS (SELECT name FROM msdb.dbo.sysalerts WHERE name = N'Error 832')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 832'

	IF EXISTS (SELECT message_id FROM msdb.sys.messages WHERE message_id = 832)
	BEGIN
		EXEC msdb.dbo.sp_add_alert @name=N'Error 832', 
			@message_id=832, 
			@severity=0, 
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=1, 
			@category_name=N'Agent Alerts Sev 24'
		EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 832', @operator_name=@customoper, @notification_method = 1
	END
	PRINT 'Agent alerts created';
END
ELSE
BEGIN
	PRINT 'Operator does not exist. Alerts were not created.';
END
GO