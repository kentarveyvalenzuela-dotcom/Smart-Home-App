# Graph Report - backend  (2026-11-24)

## Corpus Check
- 11 files · ~11,351 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 2 file(s) not represented in the graph (top: .example 1, (none) 1)

## Summary
- 216 nodes · 668 edges · 17 communities (10 shown, 7 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 28 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- post
- test_device_registration.py
- _evaluate_sensor_thresholds
- Any
- register_push_token
- _update_alert
- BaseModel
- update_device
- start_mqtt_event_listener
- health
- google_signin
- create_log
- update_preferences
- update_profile
- update_sensor_thresholds

## God Nodes (most connected - your core abstractions)
1. `_create_db_connection()` - 69 edges
2. `UserOut` - 62 edges
3. `login()` - 13 edges
4. `_evaluate_sensor_thresholds()` - 12 edges
5. `create_alert()` - 11 edges
6. `_send_push_notification()` - 10 edges
7. `_issue_email_code()` - 10 edges
8. `_get_user_by_email()` - 10 edges
9. `register()` - 10 edges
10. `create_sensor_reading()` - 10 edges

## Surprising Connections (you probably didn't know these)
- `create_notification()` --indirect_call--> `_send_push_notification()`  [INFERRED]
  app/main.py → app/main.py  _Bridges community 2 → community 4_
- `google_signin()` --indirect_call--> `_verify_google_identity_token()`  [INFERRED]
  app/main.py → app/main.py  _Bridges community 11 → community 0_
- `register()` --references--> `RegisterRequest`  [EXTRACTED]
  app/main.py → app/main.py  _Bridges community 7 → community 0_
- `AlertCreateRequest` --inherits--> `BaseModel`  [EXTRACTED]
  app/main.py →   _Bridges community 7 → community 2_
- `DeviceCreateRequest` --inherits--> `BaseModel`  [EXTRACTED]
  app/main.py →   _Bridges community 7 → community 1_

## Import Cycles
- None detected.

## Communities (17 total, 7 thin omitted)

### Community 0 - "post"
Cohesion: 0.16
Nodes (24): begin_enable_two_factor(), change_password(), _code_hash(), confirm_password_reset(), _consume_email_code(), _create_token(), _get_user_by_email(), google_signin() (+16 more)

### Community 1 - "test_device_registration.py"
Cohesion: 0.09
Nodes (7): DeviceCreateRequest, register_device(), main(), _Connection, DeviceControlMqttTests, DeviceRegistrationTests, _Result

### Community 2 - "_evaluate_sensor_thresholds"
Cohesion: 0.12
Nodes (17): AlertCreateRequest, create_alert(), create_energy_reading(), _device_owner(), DeviceSensorBatch, EnergyReadingRequest, _evaluate_sensor_thresholds(), ingest_device_energy() (+9 more)

### Community 4 - "Any"
Cohesion: 0.13
Nodes (48): _alert_filters(), clear_all_alerts(), clear_old_alerts(), clear_old_logs(), control_device(), control_device_legacy(), _create_db_connection(), create_notification() (+40 more)

### Community 5 - "register_push_token"
Cohesion: 0.67
Nodes (3): PushTokenRequest, register_push_token(), unregister_push_token()

### Community 6 - "_update_alert"
Cohesion: 0.33
Nodes (6): _alert_json(), dismiss_alert(), mark_alert_read(), mark_notification_read(), resolve_alert_legacy(), _update_alert()

### Community 7 - "BaseModel"
Cohesion: 0.15
Nodes (12): AuthTokenResponse, ChangePasswordRequest, DeviceSensorItem, EmailRequest, EmailVerificationRequest, GoogleSignInRequest, LoginRequest, NotificationRequest (+4 more)

### Community 9 - "start_mqtt_event_listener"
Cohesion: 0.25
Nodes (6): _publish_mqtt_message(), on_connect(), _record_mqtt_state(), start_mqtt_event_listener(), on_message(), stop_mqtt_event_listener()

### Community 11 - "google_signin"
Cohesion: 0.29
Nodes (6): _decode_base64(), _encode_base64(), get_current_user(), _get_user_by_id(), _verify_google_identity_token(), _verify_token()

### Community 12 - "create_log"
Cohesion: 0.67
Nodes (3): create_log(), _log_json(), LogRequest

## Knowledge Gaps
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `_evaluate_sensor_thresholds()` connect `_evaluate_sensor_thresholds` to `main.py`, `Any`?**
  _High betweenness centrality (0.044) - this node is a cross-community bridge._
- **Should `test_device_registration.py` be split into smaller, more focused modules?**
  _Cohesion score 0.08669354838709678 - nodes in this community are weakly interconnected._
- **Why does `_create_db_connection()` connect `Any` to `post`, `test_device_registration.py`, `_evaluate_sensor_thresholds`, `main.py`, `register_push_token`, `_update_alert`, `update_device`, `start_mqtt_event_listener`, `google_signin`, `create_log`, `update_preferences`, `update_profile`, `update_sensor_thresholds`?**
  _High betweenness centrality (0.038) - this node is a cross-community bridge._
- **Should `_evaluate_sensor_thresholds` be split into smaller, more focused modules?**
  _Cohesion score 0.12433862433862433 - nodes in this community are weakly interconnected._
- **Should `main.py` be split into smaller, more focused modules?**
  _Cohesion score 0.08333333333333333 - nodes in this community are weakly interconnected._
- **Should `Any` be split into smaller, more focused modules?**
  _Cohesion score 0.1262699564586357 - nodes in this community are weakly interconnected._