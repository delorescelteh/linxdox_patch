'use strict';

'require view';
'require form';
'require tools.widgets as widgets';

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('watchcat', _('Watchcat'), _(
			'Configure checks and actions to take when a host becomes unreachable or when local services become unhealthy.'
		));

		s = m.section(form.TypedSection, 'watchcat', _('Watchcat'), _(
			'These rules govern how this device reacts to network/service events.'
		));
		s.anonymous = true;
		s.addremove = true;
		s.tab('general', _('General Settings'));

		o = s.taboption('general', form.ListValue, 'mode', _('Mode'), _(
			"Ping Reboot: Reboot this device if a ping to a specified host fails for a specified duration of time. <br />" +
			"Periodic Reboot: Reboot this device after a specified interval of time. <br />" +
			"Restart Interface: Restart a network interface if a ping to a specified host fails for a specified duration of time. <br />" +
			"Service Recover: Monitor local services (e.g. Docker/ChirpStack) and attempt recovery before reboot."
		));
		o.value('ping_reboot', _('Ping Reboot'));
		o.value('periodic_reboot', _('Periodic Reboot'));
		o.value('restart_iface', _('Restart Interface'));
		o.value('service_recover', _('Service Recover（服務恢復）'));

		o = s.taboption('general', form.Value, 'period', _('Period'), _(
			"In Periodic Reboot mode, it defines how often to reboot. <br />" +
			"In Ping Reboot mode, it defines the longest period of time without a reply from the Host To Check before a reboot is engaged. <br />" +
			"In Restart Interface mode, it defines the longest period of time without a reply from the Host to Check before the interface is restarted. <br />" +
			"In Service Recover mode, it defines how long the system must stay unhealthy before reboot is allowed. <br /><br />" +
			"The default unit is seconds (no suffix), but you can use m/h/d suffixes."
		));
		o.default = '6h';

		/* Ping-based options */
		o = s.taboption('general', form.Value, 'pinghosts', _('Host To Check'), _('IPv4 address or hostname to ping.'));
		o.datatype = 'host(1)';
		o.default = '8.8.8.8';
		o.depends({ mode: 'ping_reboot' });
		o.depends({ mode: 'restart_iface' });

		o = s.taboption('general', form.Value, 'pingperiod', _('Check Interval'), _(
			'How often to ping the host specified above. Use seconds or m/h/d suffixes.'
		));
		o.default = '30s';
		o.depends({ mode: 'ping_reboot' });
		o.depends({ mode: 'restart_iface' });

		o = s.taboption('general', form.ListValue, 'pingsize', _('Ping Packet Size'));
		o.value('small', _('Small: 1 byte'));
		o.value('windows', _('Windows: 32 bytes'));
		o.value('standard', _('Standard: 56 bytes'));
		o.value('big', _('Big: 248 bytes'));
		o.value('huge', _('Huge: 1492 bytes'));
		o.value('jumbo', _('Jumbo: 9000 bytes'));
		o.default = 'standard';
		o.depends({ mode: 'ping_reboot' });
		o.depends({ mode: 'restart_iface' });

		o = s.taboption('general', form.Value, 'forcedelay', _('Force Reboot Delay'), _(
			'Applies to Ping Reboot and Periodic Reboot modes. Enter seconds to trigger delayed hard reboot if soft reboot fails; 0 disables.'
		));
		o.default = '1m';
		o.depends({ mode: 'ping_reboot' });
		o.depends({ mode: 'periodic_reboot' });

		o = s.taboption('general', widgets.DeviceSelect, 'interface', _('Interface'), _(
			'Interface to monitor and/or restart.'
		), _('<i>Applies to Ping Reboot and Restart Interface modes</i>'));
		o.depends({ mode: 'ping_reboot' });
		o.depends({ mode: 'restart_iface' });

		o = s.taboption('general', widgets.NetworkSelect, 'mmifacename', _('Name of ModemManager Interface'), _(
			'If using ModemManager, Watchcat can restart your ModemManager interface by specifying its name.'
		));
		o.depends({ mode: 'restart_iface' });
		o.optional = true;

		o = s.taboption('general', form.Flag, 'unlockbands', _('Unlock Modem Bands'), _(
			'If using ModemManager, before restarting the interface, set the modem to be allowed to use any band.'
		));
		o.default = '0';
		o.depends({ mode: 'restart_iface' });

		/* Service Recover options */
		o = s.taboption('general', form.Value, 'reboot_backoff', _('Reboot Backoff（重啟間隔）'), _(
			'兩次 reboot 的最小間隔（避免 reboot loop）。 / Minimum time between two reboots in Service Recover mode.'
		));
		o.default = '1h';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Value, 'disk_path', _('Disk Path（磁碟路徑）'), _('要檢查剩餘空間的路徑（例如 / 或 /opt）。 / Disk path to check free space for (e.g. / or /opt).'));
		o.default = '/';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Value, 'disk_min_kb', _('Minimum Free Disk (KB)（最小剩餘 KB）'), _(
			'若剩餘空間低於此門檻，會視為 unhealthy 並記錄告警。 / If free space is below this threshold, system is marked unhealthy.'
		));
		o.datatype = 'uinteger';
		o.default = '200000';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Flag, 'docker_check', _('Docker Health Check（Docker 健康檢查）'), _(
			'啟用後會檢查 `docker info`，不健康時嘗試重啟 dockerd。 / When enabled, checks `docker info` and restarts dockerd if unhealthy.'
		));
		o.default = '1';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Flag, 'chirpstack_check', _('ChirpStack Stack Check（ChirpStack 檢查）'), _(
			'啟用後會檢查 ChirpStack 容器並嘗試自動修復。 / When enabled, checks ChirpStack containers and tries recovery.'
		));
		o.default = '1';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Value, 'chirpstack_name_prefix', _('ChirpStack Container Prefix'), _(
			'Only containers whose names start with this prefix are considered part of the ChirpStack stack.'
		));
		o.default = 'chirpstack-docker_';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.DynamicList, 'chirpstack_required', _('ChirpStack Required Components'), _(
			'Keywords (substring match) that must appear in running container names under the prefix.'
		));
		o.depends({ mode: 'service_recover' });
		o.optional = true;

		o = s.taboption('general', form.Value, 'chirpstack_compose_dir', _('ChirpStack Compose Directory'), _(
			'Directory containing the docker-compose.yml used to recover the stack.'
		));
		o.default = '/mnt/opensource-system/chirpstack-docker';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.ListValue, 'chirpstack_recover', _('ChirpStack Recover Strategy'), _(
			'Choose recovery strategy when ChirpStack stack is unhealthy.'
		));
		o.value('docker_restart_then_compose', _('Restart containers then Compose up'));
		o.value('compose_up', _('Compose up only'));
		o.default = 'docker_restart_then_compose';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Value, 'chirpstack_recover_cooldown', _('ChirpStack Recover Cooldown (seconds)'), _(
			'Minimum seconds between two ChirpStack recover attempts.'
		));
		o.datatype = 'uinteger';
		o.default = '300';
		o.depends({ mode: 'service_recover' });

		return m.render();
	}
});
