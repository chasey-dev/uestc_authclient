'use strict';
'require ui';
'require view';
'require dom';
'require poll';
'require uci';
'require fs';
'require form';
'require tools.widgets as widgets'; // Assuming widgets like DeviceSelect might be useful later
'require rpc'; // Needed for callInitAction

// Helper function to execute manager script commands
function callManager(command, sid) {
    let args = [command];
    if (sid) {
        args.push(sid);
    }
    // Need to handle potential errors and parse JSON for status
    return fs.exec('/usr/bin/uestc_authclient_manager.sh', args).then(function(res) {
        // console.log('callManager response for:', command, args, 'Code:', res.code, 'Stdout:', res.stdout, 'Stderr:', res.stderr); // DEBUG
        if (res.code !== 0) {
            throw new Error('Manager script execution failed: ' + (res.stderr || res.stdout || 'Unknown error'));
        }
        if (command === 'status') {
            try {
                // manager.sh status returns JSON like { "sessions": [...] } 
                let parsedData = JSON.parse(res.stdout);
                // Extract the sessions array, default to empty array if structure is wrong
                if (parsedData && Array.isArray(parsedData.sessions)) {
                    return parsedData.sessions;
                } else {
                    console.warn('Received status data is not in the expected { sessions: [...] } format:', parsedData);
                    return []; // Return empty array to avoid breaking downstream code
                }
            } catch (e) {
                console.error('Failed to parse JSON status:', res.stdout, e);
                throw new Error('Failed to parse status JSON: ' + e.message);
            }
        }
         if (command === 'log') {
            // log command returns plain text
            return res.stdout || '';
        }
        // For start/stop/restart, just check exit code (handled above)
        return true;
    }).catch(function(err) {
        ui.addNotification(null, E('p', _('Error executing command:') + ' ' + err.message));
        return Promise.reject(err); // Propagate rejection
    });
}

return view.extend({
    // For formatting timestamps later
    datestr: function(ts) {
        if (!ts || ts <= 0) return _('None');
        let date = new Date(ts * 1000);
        return date.toLocaleString();
    },

    // Declare calls to init script for global service control
    callInitAction: rpc.declare({
        object: 'luci',
        method: 'setInitAction',
        params: [ 'name', 'action' ],
        expect: { result: false }
    }),

    // Backend Interaction Wrappers (using callManager helper)
    callGetStatus: function(sid) {
        return callManager('status', sid);
    },

    callStartSession: function(sid) {
        return callManager('start', sid);
    },

    callStopSession: function(sid) {
        return callManager('stop', sid);
    },

    callRestartSession: function(sid) {
        return callManager('restart', sid);
    },

    callGetLogs: function(sid) {
        return callManager('log', sid);
    },

    load: function() {
        return Promise.all([
            uci.load('uestc_authclient'),
            this.callGetStatus() // Get status for all sessions initially
        ]);
    },

    render: function(data) {
        let uciData = data[0]; // UCI data loaded
        let initialStatus = data[1] || []; // Initial status array
        let self = this; // Capture the main view context

        let m, s, o;

        m = new form.Map('uestc_authclient', _('UESTC Authentication Client'),
            _('This page displays the current status of the UESTC authentication client. Please adjust other settings as needed.'));

        // --- Global Section --- (Mimicking ddns layout)
        s = m.section(form.NamedSection, 'global', 'system');
        // s.title = _('Settings');
        s.tab('info', _('Status & Control'));
        s.tab('global_settings', _('Global Settings'));

        // Info Tab - Global Service Status/Control
        o = s.taboption('info', form.Flag, 'enabled', _('Enable on startup'));
        o.description = _('Check to run the service automatically at system startup.');
        o.default = '0';
        o.rmempty = false;

        // o = s.taboption('info', form.Button, '_start_stop');
        // o.title = '&#160;';
        // o.inputstyle = 'apply';
        // o.inputtitle = _('Loading...'); // Will be updated by poll
        // o.onclick = L.bind(function(ev) {
        //     return L.resolveDefault(rpc.call('luci', 'getInitAction', { name: 'uestc_authclient', action: 'enabled' }), false)
        //         .then(L.bind(function(isEnabled) {
        //             const action = isEnabled ? 'stop' : 'start';
        //             ui.showModal(_('Confirm Action'), [
        //                 E('p', action === 'start' ? _('Start the UESTC Auth service?') : _('Stop the UESTC Auth service?')),
        //                 E('div', { 'class': 'right' }, [
        //                     E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')),
        //                     ' ',
        //                     E('button', {
        //                         'class': 'cbi-button cbi-button-positive important',
        //                         'click': ui.createHandlerFn(this, function(action) {
        //                             return this.callInitAction('uestc_authclient', action)
        //                                    .then(function() { window.location.reload(); }) // Reload page instead of map render
        //                                    .catch(function(e) { ui.addNotification(null, E('p', e.message)); });
        //                         }, action)
        //                     }, action === 'start' ? _('Start Service') : _('Stop Service'))
        //                 ])
        //             ]);
        //         }, this));
        // }, this);

        o = s.taboption('info', form.Button, '_restart');
        o.title = '&#160;';
        o.inputstyle = 'reload';
        o.inputtitle = _('Restart Service');
        o.onclick = L.bind(function(ev) {
             ui.showModal(_('Confirm Action'), [
                E('p', _('Restart the UESTC Auth service?')),
                E('div', { 'class': 'right' }, [
                    E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')),
                    ' ',
                    E('button', {
                        'class': 'cbi-button cbi-button-positive important',
                        'click': ui.createHandlerFn(this, function() {
                             return this.callInitAction('uestc_authclient', 'restart')
                                   .then(function() { window.location.reload(); }) // Reload page instead of map render
                                   .catch(function(e) { ui.addNotification(null, E('p', e.message)); });
                        })
                    }, _('Restart Service'))
                ])
            ]);
        }, this);

        // Global Log Button (Modified for Inline Toggle)
        o = s.taboption('info', form.Button, '_show_global_log');
        o.title = _('Global Logs');
        o.inputstyle = 'apply';
        o.inputtitle = _('View Global Log');
        o.onclick = L.bind(function(ev) {
            //  console.log('Global log button clicked');
             let logDisplay = document.getElementById('global_log_display_area');
             if (logDisplay) {
                //  console.log('Global log display found');
                 if (logDisplay.style.display === 'none') {
                     logDisplay.style.display = 'block';
                     logDisplay.value = _('Loading logs...');
                     self.callGetLogs('global').then(function(logText) {
                        //  console.log('Global logs received');
                         logDisplay.value = logText || _('No global logs available.');
                         logDisplay.scrollTop = logDisplay.scrollHeight; // Scroll to bottom
                     }).catch(function(e){
                          console.error('Error loading global logs:', e);
                          logDisplay.value = _('Failed to load logs.') + ' ' + e.message;
                     });
                 } else {
                     logDisplay.style.display = 'none';
                 }
             } else {
                  console.error('Global log display area not found!');
             }
        }, self);

        // Global Log Display Area (DummyValue + Render)
        o = s.taboption('info', form.DummyValue, '_global_log_display');
        o.render = function() {
            const id = 'global_log_display_area';
        
            const textarea = E('textarea', {
                id:    id,
                rows:  20,
                readonly: 'readonly',
                wrap:  'off',
                class: 'cbi-input-textarea',
                style: [
                    'width: 100%',
                    // 'font-family: monospace',
                    // 'font-size: 15px',
                    'box-sizing:border-box',
                    'display: none' // Initially hidden
                ].join(';')
            });

            return E('div', {
                style: [
                    'display:flex',
                    'justify-content:center',   // align horizontally
                    'padding:8px 0'
                ].join(';')
            }, [ textarea ]);
        };

        // Global Settings Tab
        o = s.taboption('global_settings', form.Value, 'log_rdays', _('Log retention days (Global)'));
        o.description = _('Specify the number of days to retain global log files.');
        o.datatype = 'uinteger';
        o.placeholder = '7';

        // --- Sessions Grid Section --- 
        s = m.section(form.GridSection, 'session', _('Authentication Sessions'));
        s.anonymous = true;
        s.addremove = true;
        s.sortable = true;
        s.addbtntitle = _('Add new session...');

        // Define Grid Columns (Placeholders for now, logic in poll_status)
        o = s.option(form.DummyValue, '_cfg_name', _('Name'));
        o.textvalue = function(section_id) { return '<b>' + section_id + '</b>'; };

        o = s.option(form.Flag, 'enabled', _('Enabled'));
        o.editable = true;

        o = s.option(form.DummyValue, '_cfg_status', _('Status'));

        o = s.option(form.DummyValue, '_cfg_network', _('Network Status'));

        o = s.option(form.DummyValue, '_cfg_last_login', _('Last Login Time'));

        s.handleAdd = function () {
            const map  = this.map;
        
            // actual validate session ID
            function validateSid(sid, existing) {
                if (!sid)             return _('Session name cannot be empty.');
                if (['global','basic','_new_'].includes(sid))
                    return _('This name is reserved, please choose another.');
        
                // allowed chars: A–Z a–z 0–9 - _ , length 1-32
                if (!/^[A-Za-z0-9_-]{1,32}$/.test(sid))
                    return _('Only letters, numbers, “-” and “_” are allowed (1-32 chars).');
        
                if (existing.includes(sid))
                    return _('Session name already exists.');
                return null;          // everything is ok
            }
        
            // get existing session IDs
            const existingSids = uci.sections('uestc_authclient', 'session')
                                    .map(s => s['.name']);
        
            // build modal elements
            const inputSid = E('input', {
                id:    'new_sid',
                type:  'text',
                style: 'width:100%; margin-top:8px;'
            });
        
            const errorMsg = E('div', {
                style: 'display:none; color:#d9534f; margin-top:4px;'
            });
        
            // create button disabled until validation passes
            const btnCreate = E('button', {
                class: 'cbi-button cbi-button-positive important',
                disabled: true
            }, _('Create'));
        
            // validate real-time
            function refreshValidation() {
                const sid  = inputSid.value.trim();
                const info = validateSid(sid, existingSids);
        
                if (info) {
                    errorMsg.textContent   = info;
                    errorMsg.style.display = 'block';
                    btnCreate.disabled     = true;
                } else {
                    errorMsg.style.display = 'none';
                    btnCreate.disabled     = false;
                }
            }
            inputSid.addEventListener('input', refreshValidation);
        
            // click handler for the Create button
            btnCreate.addEventListener('click', async () => {
                const sid = inputSid.value.trim();
        
                // double-check sid
                const err = validateSid(sid, existingSids);
                if (err) { refreshValidation(); return; }
                // write UCI
                // too much UCI calls may add overhead, use default values in UI
                uci.add('uestc_authclient','session', sid);
                ui.hideModal();
        
                // refresh table and open Edit row automatically
                const nodes = await map.render();
                nodes.querySelector(
                    `.cbi-section-table-row[data-sid="${sid}"] .cbi-button-edit`
                )?.click();
            });

            // show modal
            ui.showModal(_('Add new session...'), [
                E('p', _('Please enter a new session name: (avoid using reserved names like "global")')),
                inputSid,
                errorMsg,
                E('div', { class: 'right' }, [
                    E('button', { class: 'btn', click: ui.hideModal }, _('Cancel')),
                    ' ',
                    btnCreate
                ])
            ]);
        
            // focus on the input field
            inputSid.focus();
        };

         // Edit Modal Title
         s.modaltitle = function(section_id) {
            return _('Session Configuration') + ' >> ' + section_id;
        };

        // Edit Modal Options (Structure)
        s.addModalOptions = function(modalSection, section_id) { // First arg is the ModalSection instance
            modalSection.tab('auth', _('Authentication Settings'));
            modalSection.tab('network', _('Network Settings'));
            modalSection.tab('schedule', _('Scheduled Disconnection'));
            modalSection.tab('logging', _('Logging Settings'));
            // modalSection.tab('logview', _('Log Viewer'));

            // Authentication Tab Options
            o = modalSection.taboption('auth', form.Flag, 'enabled', _('Enabled'));
            o.default = '0';
            o.rmempty = false;

            o = modalSection.taboption('auth', form.Flag, 'lm_enabled', _('Limited Monitoring'));
            o.description = _('Check to limit monitoring and reconnection attempts to within 10 minutes around the last login time.');
            o.default = '0';
            o.rmempty = false;

            o = modalSection.taboption('auth', form.ListValue, 'auth_type', _('Authentication method'));
            o.description = _('Select the authentication method. New dormitories and teaching areas use the ' + 
                                'Srun authentication method.');
            o.value('srun', _('Srun authentication method (go-nd-portal)'));
            o.value('ct', _('CT authentication method (qsh-telecom-autologin)'));
            o.default = 'srun';
            o.rmempty = false;

            o = modalSection.taboption('auth', form.ListValue, 'auth_mode', _('Srun authentication mode'));
            o.description = _('Select the authentication mode for the Srun client.');
            o.value('dx', _('China Telecom'));
            o.value('edu', _('Campus Network'));
            o.default = 'dx';
            o.depends('auth_type', 'srun');

            o = modalSection.taboption('auth', form.Value, 'auth_username', _('Username'));
            o.description = _('Your authentication username.')
            o.placeholder = _('Required');
            o.rmempty = false;
            o.validate = function(section_id, value) { if (!value) return _('Username cannot be empty.'); return true; };

            o = modalSection.taboption('auth', form.Value, 'auth_password', _('Password'));
            o.description = _('Your authentication password.')
            o.password = true;
            o.placeholder = _('Required');
            o.rmempty = false;
            o.validate = function(section_id, value) { if (!value) return _('Password cannot be empty.'); return true; };

            o = modalSection.taboption('auth', form.Value, 'auth_host', _('Authentication Host'));
            o.description = _('Authentication server address, modify according to your area.')
            o.datatype = 'ip4addr';
            o.placeholder = '10.253.0.237';
            o.rmempty = false;
            
            // Network Tab Options
            o = modalSection.taboption('network', widgets.DeviceSelect, 'listen_interface', _('Interface'));
            o.description = _('Select the interface for authentication. (Linux Interface, Refers to Device in Openwrt.)')
            o.noaliases = true; // Typically want physical devices
            o.default = 'wan';
            o.rmempty = false;

            o = modalSection.taboption('network', form.DynamicList, 'listen_hosts', _('Heartbeat hosts'));
            o.description = _('Host addresses used to check network connectivity; you can add multiple ' +
                                'addresses.');
            o.datatype = 'ip4addr'
            o.default = ["223.5.5.5", "119.29.29.29"];
            o.placeholder = '223.5.5.5';
            o.rmempty = false;

            o = modalSection.taboption('network', form.Value, 'listen_check_interval', _('Check interval (seconds)'));
            o.description = _('Time interval for checking network status, in seconds.')
            o.datatype = 'uinteger';
            o.default = '30'
            o.placeholder = '30';
            o.rmempty = false;

            // Schedule Tab Options
            o = modalSection.taboption('schedule', form.Flag, 'schedule_enabled', _('Enable scheduled disconnection'));
            o.description = _('Check to disconnect the network during specified time periods.');
            o.default = '0';
            o.rmempty = false;

            o = modalSection.taboption('schedule', form.Value, 'schedule_start', _('Disconnection start time (hour)'));
            o.datatype = 'range(0,23)';
            // dont remove default and rmempty here to prevent UI bugs
            o.default = '3';
            o.placeholder = '3';
            o.rmempty = false;
            o.depends('schedule_enabled', '1');

            o = modalSection.taboption('schedule', form.Value, 'schedule_end', _('Disconnection end time (hour)'));
            o.datatype = 'range(0,23)';
            // dont remove default and rmempty here to prevent UI bugs
            o.default = '4';
            o.placeholder = '4';
            o.rmempty = false;
            o.depends('schedule_enabled', '1');
            o.validate = function(section_id, value) { // section_id here is the schedule section name
                 let start = this.section.formvalue(section_id, 'schedule_start');
                 if (start && value && start === value) {
                     return _('Disconnection start time and end time cannot be the same!');
                 }
                 return true;
            };

            // Logging Tab Options
            o = modalSection.taboption('logging', form.Value, 'log_rdays', _('Log retention days (Session)'));
            o.description = _('Specify the number of days to retain session log files.');
            o.datatype = 'uinteger';
            o.default = '7';
            o.placeholder = '7';
            o.rmempty = false;

            // Log Viewer - Inline display
            o = modalSection.taboption('logging', form.Button, '_read_log');
            o.title = _('Log Viewer');
            o.inputtitle = _('Read / Reread log file');
            o.inputstyle = 'apply';
            o.onclick = L.bind(function(sid, ev) {
                // console.log('Session log button clicked for:', sid);
                let logDisplay = document.getElementById('log_display_area_' + sid);
                if (logDisplay) {
                    //  console.log('Session log display found');
                    if (logDisplay.style.display === 'none') { // Toggle logic
                        logDisplay.style.display = 'block'; // Make visible
                        logDisplay.value = _('Loading logs...');
                        // Ensure 'self' refers to the view instance
                        return self.callGetLogs(sid).then(function(logText) {
                            //  console.log('Session logs received for:', sid);
                            logDisplay.value = logText || _('No logs available');
                            logDisplay.scrollTop = logDisplay.scrollHeight; // Scroll to bottom
                        }).catch(function(e){
                             console.error('Error loading session logs for:', sid, e);
                             logDisplay.value = _('Failed to load logs.') + ' ' + e.message;
                        });
                    } else {
                        logDisplay.style.display = 'none'; // Hide
                    }
                } else {
                    console.error('Session log display area not found for:', sid);
                }
            }, self, section_id);

            o = modalSection.taboption('logging', form.DummyValue, '_log_display'); // Placeholder for the textarea
            o.modalonly = true;
            o.render = function(option_index, section_id, container) {
                const id = 'log_display_area_' + section_id;

                const textarea = E('textarea', {
                    id:    id,
                    rows:  20,
                    readonly: 'readonly',
                    wrap:  'off',
                    class: 'cbi-input-textarea',
                    style: [
                        'width: 100%',
                        // 'font-family: monospace',
                        // 'font-size: 15px',
                        'box-sizing:border-box',
                        'display: none' // Initially hidden
                    ].join(';')
                });

                return E('div', {
                    style: [
                        'display:flex',
                        'justify-content:center',   // align horizontally
                        'padding:8px 0'
                    ].join(';')
                }, [ textarea ]);
            };
        };

        // Row Actions (Modified for combined Start/Stop)
        s.renderRowActions = function(section_id) {
            // Call super to get the td element which should contain the default Edit and Remove buttons
            // inside its last child element (usually a div or span)
            let tdEl = this.super('renderRowActions', [ section_id, _('Edit') ]);

            // Create combined Start/Stop button
            let startStopBtn = E('button', {
                'class': 'cbi-button cbi-button-action start-stop',
                'title': _('Start/Stop this session')
            }, _('Loading...')); // Text will be set by poll_status

            // Create Restart button
            let restartBtn = E('button', {
                'class': 'cbi-button cbi-button-action restart',
                'click': ui.createHandlerFn(self, 'handleSessionAction', section_id, 'restart'),
                'title': _('Restart this session')
            }, _('Restart'));

            // Create space nodes for separation
            let space1 = document.createTextNode(' ');
            let space2 = document.createTextNode(' ');

            // Get the container where the default buttons (Edit, Remove) reside
            let buttonContainer = tdEl.lastChild;

            // Get the first existing node within the container (likely the Edit button or its wrapper)
            let firstExistingButton = buttonContainer.firstChild;

            // Insert the new buttons and spaces before the first existing button using standard insertBefore
            if (firstExistingButton) {
                buttonContainer.insertBefore(startStopBtn, firstExistingButton);
                buttonContainer.insertBefore(space1, firstExistingButton); // Insert space after start/stop
                buttonContainer.insertBefore(restartBtn, firstExistingButton); // Insert restart before edit
                buttonContainer.insertBefore(space2, firstExistingButton); // Insert space after restart
            } else {
                // Fallback if the container is somehow empty (shouldn't happen with Edit/Remove)
                // Use dom.append for appending multiple nodes easily
                dom.append(buttonContainer, [startStopBtn, space1, restartBtn, space2]);
            }

            return tdEl;
        };

        // --- Rendering & Polling --- 
        return m.render().then(L.bind(function(map, nodes) {
            // Initial status update based on load data
            this.poll_status(nodes, initialStatus);

            poll.add(L.bind(function() {
                return this.callGetStatus().then(L.bind(this.poll_status, this, nodes));
            }, this), 5);
            return nodes;
        }, this, m));
    },

    // Function to handle Start/Stop/Restart clicks
    handleSessionAction: function(sid, action, ev) {
        const targetButton = ev.target; 
        const row = targetButton.closest('.cbi-section-table-row'); 
        const nodes = targetButton.closest('.cbi-map'); 

        // Disable Start/Stop, Restart, Edit, Remove buttons in this row during action
        if (row) {
            row.querySelectorAll('.start-stop, .restart, .cbi-button-edit, .cbi-button-remove').forEach(btn => btn.disabled = true);
        }

        let promise;
        switch(action) {
            case 'start': promise = this.callStartSession(sid); break;
            case 'stop': promise = this.callStopSession(sid); break;
            case 'restart': promise = this.callRestartSession(sid); break;
            default: promise = Promise.reject('Invalid action');
        }

        // Chain the status update and button re-enabling
        return promise.then(() => {
            // Wait a tiny bit for backend state to potentially update before refreshing UI
            return new Promise(resolve => setTimeout(resolve, 500));
        }).then(() => {
            // Manually refresh status after the short delay
            return this.callGetStatus().then(L.bind(function(sessionsStatus) {
                if (nodes) { // Ensure we found the map nodes
                     this.poll_status(nodes, sessionsStatus); // Call the existing polling function to update UI
                } else {
                    console.error("Could not find map nodes for status update.");
                }
            }, this)); // Ensure 'this' context for poll_status
        }).catch(err => {
            // Log or notify error if needed, but proceed to hide indicator
            console.error('Session action failed:', err);
            ui.addNotification(null, E('p', _('Action failed: %s').format(err.message || err)));
            // Optionally, re-fetch status even on error to reflect potential partial changes or failures
            return this.callGetStatus().then(L.bind(function(sessionsStatus) {
                if (nodes) {
                    this.poll_status(nodes, sessionsStatus);
                }
            }, this));
        }).finally(() => {
            // Always hide the indicator on the specific button, regardless of success/failure
            // ui.hideIndicator(targetButton);
            // Re-enable only Edit/Remove buttons here. 
            // poll_status will handle enabling/disabling Start/Stop and Restart based on the fetched status.
            if (row) {
                 row.querySelectorAll('.cbi-button-edit, .cbi-button-remove').forEach(btn => btn.disabled = false);
            }
        });
    },

    // Polling function to update status in the grid
    poll_status: function(nodes, statusData) {
        let gridRows = nodes.querySelectorAll('.cbi-section-table-row[data-sid]');
        let statusMap = {};

        // Create a map for easy lookup
        if (Array.isArray(statusData)) {
            statusData.forEach(s => { statusMap[s.sid] = s; });
        }

        gridRows.forEach(row => {
            let sid = row.getAttribute('data-sid');
            let status = statusMap[sid];

            let statusCell = row.querySelector('[data-name="_cfg_status"]');
            let networkCell = row.querySelector('[data-name="_cfg_network"]');
            let loginCell = row.querySelector('[data-name="_cfg_last_login"]');
            
            // Select the specific buttons
            let startStopBtn = row.querySelector('.cbi-button.start-stop');
            let restartBtn = row.querySelector('.cbi-button.restart');

            // Ensure buttons exist before trying to modify them
            if (!startStopBtn || !restartBtn) {
                 console.warn(`Buttons not found for SID: ${sid}`);
                 return; // Skip this row if buttons aren't rendered yet
            }

            if (status) {
                // Update status text
                dom.content(statusCell, status.running ? E([], [E('strong', {style: 'color:green'}, _('Running')), ' (PID: ' + status.pid + ')']) : E('strong',{style:'color:red'},_('Not running')));
                if(status.running) {
                    dom.content(networkCell, status.network_up ? E('strong', {style: 'color:green'}, _('Connected')) : E('strong',{style:'color:red'},_('Disconnected')));
                }else{
                    dom.content(networkCell, E('em', _('Not running')));
                }
                dom.content(loginCell, this.datestr(status.last_login));

                // Update Start/Stop button
                let currentAction = status.running ? 'stop' : 'start';
                startStopBtn.textContent = status.running ? _('Stop') : _('Start');
                startStopBtn.onclick = ui.createHandlerFn(this, 'handleSessionAction', sid, currentAction);
                startStopBtn.disabled = false; // Enable the button

                // Update Restart button state
                 if (restartBtn) restartBtn.disabled = !status.running;

            } else {
                // Session status unknown
                dom.content(statusCell, E('em', _('Unknown')));
                dom.content(networkCell, E('em', _('Unknown')));
                dom.content(loginCell, E('em', _('Unknown')));
                
                // Disable buttons if status is unknown
                startStopBtn.textContent = _('Start'); // Default text
                startStopBtn.onclick = null; // Remove handler
                startStopBtn.disabled = true;

                // Update Restart button state
                 if (restartBtn) restartBtn.disabled = true;
            }
        });

        // // Update global start/stop button title
        //  let startStopBtn = nodes.querySelector('[data-name="_start_stop"] button');
        //  if (startStopBtn) {
        //      L.resolveDefault(rpc.call('luci', 'getInitAction', { name: 'uestc_authclient', action: 'enabled' }), false)
        //          .then(function(isEnabled) {
        //              startStopBtn.textContent = isEnabled ? _('Stop Service') : _('Start Service');
        //          });
        //  }

    }
}); 