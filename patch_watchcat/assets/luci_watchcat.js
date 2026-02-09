'use strict';

'require view';
'require form';
'require tools.widgets as widgets';

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('watchcat', _('Watchcat（看門狗）'), _(
			'設定當主機不可達或本機服務不健康時的檢查與動作（Configure checks and actions when a host is unreachable or local services are unhealthy）。'
		));

		s = m.section(form.TypedSection, 'watchcat', _('Watchcat'), _(
			'這些規則定義設備對網路/服務事件的反應方式（These rules govern how this device reacts to network/service events）。'
		));
		s.anonymous = true;
		s.addremove = true;
		s.tab('general', _('一般設定（General Settings）'));

		o = s.taboption('general', form.ListValue, 'mode', _('模式（Mode）'), _(
			"Ping Reboot（Ping 重啟）：若對指定主機 ping 失敗持續一段時間，則重啟設備。 <br />" +
			"Periodic Reboot（週期性重啟）：每隔指定時間重啟設備。 <br />" +
			"Restart Interface（重啟介面）：若對指定主機 ping 失敗持續一段時間，則重啟指定網路介面。 <br />" +
			"Service Recover（服務恢復）：監控本機服務（例如 Docker/ChirpStack），優先嘗試修復，必要時才 reboot。"
		));
		o.value('ping_reboot', _('Ping Reboot（Ping 重啟）'));
		o.value('periodic_reboot', _('Periodic Reboot（週期性重啟）'));
		o.value('restart_iface', _('Restart Interface（重啟介面）'));
		o.value('service_recover', _('Service Recover（服務恢復）'));

		o = s.taboption('general', form.Value, 'period', _('週期（Period）'), _(
			"Periodic Reboot：定義多久重啟一次。 <br />" +
			"Ping Reboot：定義 Host 多久沒回應才會觸發重啟。 <br />" +
			"Restart Interface：定義 Host 多久沒回應才會重啟介面。 <br />" +
			"Service Recover：系統不健康持續多久後才允許 reboot（避免短暫抖動就重啟）。 <br /><br />" +
			"預設單位為秒（不加尾綴），也可用 m（分鐘）/ h（小時）/ d（天）。（Default unit is seconds; supports m/h/d suffixes.）"
		));
		o.default = '6h';

		/* Ping-based options */
		o = s.taboption('general', form.Value, 'pinghosts', _('要檢查的主機（Host To Check）'), _('要 ping 的 IPv4/主機名（IPv4 address or hostname to ping）。'));
		o.datatype = 'host(1)';
		o.default = '8.8.8.8';
		o.depends({ mode: 'ping_reboot' });
		o.depends({ mode: 'restart_iface' });

		o = s.taboption('general', form.Value, 'pingperiod', _('檢查間隔（Check Interval）'), _(
			'多久 ping 一次上方指定主機；可用秒或 m/h/d 尾綴（How often to ping; supports seconds or m/h/d suffixes）。'
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
