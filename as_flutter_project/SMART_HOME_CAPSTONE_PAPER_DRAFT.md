# BRIX Smart Home IoT System

## Capstone Paper Draft

**Working title:** Design and Development of BRIX: A Flutter-Based Smart Home IoT Monitoring and Device Control System

**Prepared by:** [Names of proponents]  
**Institution:** [School / department]  
**Adviser:** [Name]  
**Academic year:** [Academic year]

> **Draft note.** This draft is based on the source code and project documentation currently in the repository. Replace bracketed fields with verified project and school information. No respondent counts, test outcomes, performance measurements, or claims of completed hardware integration have been invented. The repository README says that the ESP32 batch-ingest and full sensor-history routes are not yet wired to the backend; reflect the implementation actually demonstrated at defense time.

## Abstract

Residential electrical appliances and household devices are often controlled locally, making it difficult for users to check their status when they are away or to keep a consolidated record of device activity. This project presents BRIX, a smart home Internet of Things (IoT) application with a Flutter client, a Python FastAPI backend, a PostgreSQL data store, and MQTT-based device communication. The application provides account access, device registration and control, user preferences, activity logs, notifications, and an energy-monitoring interface. The backend supports authenticated APIs, MQTT command publishing, configurable sensor thresholds, and alert and notification records. An ESP32-based device is part of the intended hardware setup; readings can be submitted through the authenticated test-reading route, while the repository documentation identifies batch ingestion from firmware and complete sensor-history retrieval as pending integration.

The system was developed using [insert actual development process]. Its evaluation will cover functional correctness, usability, and [other approved criteria] using [identify instruments, participants, and test environment]. The results section must be completed from observed data after testing. The project aims to provide a single interface for home device control and monitoring while documenting the integration limits that remain in the current build.

**Keywords:** Internet of Things, smart home, Flutter, FastAPI, MQTT, ESP32, energy monitoring

## Chapter 1. The Problem and Its Background

### Background of the Study

Internet-connected sensors and actuators can allow household devices to be monitored and controlled through a networked application. Such arrangements may help a user check appliance state, issue a control command remotely, and receive a notice when monitored values cross a configured limit. A practical system must coordinate the user interface, server-side account and data handling, messaging between software and hardware, and the physical device itself.

BRIX is a prototype smart home system intended to combine these functions. Its client is written in Flutter and includes screens for authentication, a home dashboard, device management, energy monitoring, logs, notifications, and settings. The backend is built with FastAPI and stores application data in PostgreSQL. MQTT is used to communicate device-control commands, and the repository includes ESP32 firmware and setup material. The system also includes account preferences, email-based verification features, optional Google sign-in, threshold settings, and push-notification support when the required services are configured.

The implementation is not complete in every end-to-end path. The project README states that the ESP32 batch-ingest endpoint and full sensor-history read routes are not yet connected to the backend. The current paper therefore treats the software as a developed prototype and distinguishes implemented, configurable, and pending components. This distinction is necessary for an accurate evaluation and for future development planning.

### Statement of the Problem

This project addresses the need for a unified prototype through which an authenticated user can manage supported home devices and view related system information. Specifically, it seeks to answer:

1. How can a cross-platform application and backend be designed to support account access, device management, and MQTT-based device commands?
2. How can the system present device activity, notifications, and configurable electrical thresholds to the user?
3. To what extent does the implemented prototype meet the functional and usability criteria defined for the project when evaluated in a controlled test environment?

Question 3 must be answered using actual test observations and approved evaluation instruments; this draft does not assert a result.

### Objectives of the Study

**General objective:** To design, develop, and evaluate a prototype smart home IoT system for managing supported devices and presenting monitoring and alert information through a Flutter application.

**Specific objectives:**

1. Develop a Flutter client with authentication, dashboard, device, monitoring, log, notification, and settings screens.
2. Develop a FastAPI backend with authenticated endpoints and PostgreSQL persistence for supported account and application data.
3. Implement MQTT-based device-control communication between the backend and configured devices.
4. Provide configurable voltage and current thresholds and represent out-of-range events through the supported alert flow.
5. Evaluate the implemented features using a documented test plan and report observed results without extrapolating beyond the tested environment.

### Scope and Delimitations

The project covers a Flutter mobile/web client, a FastAPI backend, PostgreSQL migrations, MQTT communication, and ESP32-related setup/firmware materials. Features represented in the repository include authentication and account settings, device registration and control, activity logs, notification handling, and energy-monitoring screens. Backend routes include device management and control, account settings, logs, notifications, and other authenticated operations. Email delivery, Google identity verification, Firebase push delivery, PostgreSQL, and the MQTT broker require correct external configuration to operate.

The available project documentation explicitly notes that firmware batch sensor ingestion and full sensor-history retrieval are not yet wired into the backend. A test-reading endpoint is described for exercising threshold evaluation without an ESP32. Therefore, this draft does not claim continuous hardware-to-database sensor history unless that integration is completed and demonstrated. Results will be limited to the devices, accounts, network, configuration, and test duration actually used. This system is a prototype and is not presented as a certified electrical safety device or a substitute for qualified installation.

### Significance of the Study

- **Household users:** A single interface may make supported device controls and status information easier to access.
- **Project developers:** The modular client, API, persistence, and messaging components provide a basis for continued integration and testing.
- **Future researchers:** The documented scope and remaining sensor-ingestion work can inform improvements to smart home monitoring prototypes.
- **Academic evaluators:** The paper provides a traceable description of the implementation and a place to report measured outcomes.

These are intended benefits; their realization should be assessed through the project's evaluation.

### Definition of Terms

- **API:** Application Programming Interface used by the client and backend to exchange requests and responses.
- **ESP32:** A microcontroller platform used in the project's hardware materials for network-connected sensing or control.
- **FastAPI:** Python framework used to implement the backend HTTP API.
- **IoT:** Internet of Things; network-connected physical devices that can exchange data or commands.
- **MQTT:** Publish/subscribe messaging protocol used by the system for device communication.
- **PostgreSQL:** Relational database configured by the project for persistent application data.
- **Threshold:** A configured upper or lower measurement limit used to determine whether a reading is out of range.

## Chapter 2. Review of Related Concepts and System Design

### Related Concepts

**Smart home systems.** A smart home system links devices, sensors, communication services, and user-facing controls. Reliability depends on how these components coordinate and how failures such as network loss are represented to the user.

**Cross-platform application development.** Flutter enables a shared Dart codebase to target supported platforms. In BRIX, Flutter provides the interface and client-side service classes that communicate with the backend and, where configured, the messaging service.

**Web APIs and persistence.** The FastAPI backend exposes endpoints for application operations. PostgreSQL migrations define persistent data structures. Authentication and per-user authorization are important because device and account data must be scoped to the signed-in user.

**Publish/subscribe messaging.** MQTT separates publishers and subscribers through a broker and topics. BRIX's documented command path publishes control requests to device-specific topics. Successful control depends on broker availability, valid credentials, topic agreement, and a correctly configured device.

**Sensor threshold alerts.** A threshold evaluator compares readings with user-configured limits and records an alert when a value is outside the permitted range. BRIX's README describes testing this path through an authenticated sensor-reading request and states that firmware ingestion remains pending.

### Conceptual Framework (Input–Process–Output)

| Input | Process | Output |
|---|---|---|
| User credentials and preferences | Authenticate user and authorize API requests | User session and account settings |
| Device details and control action | Validate ownership; persist device details; publish MQTT command | Device record and command response |
| Sensor reading and configured limits | Validate reading; compare with limits; create or resolve alert state | Reading evaluation and alert/notification record |
| User activity and application events | Record and retrieve logs and notifications | Activity history and user-facing notices |
| External configuration (database, broker, email, Firebase) | Connect optional infrastructure services | Enabled deployment-specific capabilities |

The sensor input path from ESP32 firmware to complete historical readings is a stated integration limitation in the current repository documentation.

### System Architecture

The system can be described in four layers:

1. **Presentation layer:** Flutter screens and reusable widgets.
2. **Application/service layer:** Flutter service classes for authentication, API access, device handling, synchronization, monitoring, and notifications.
3. **Backend and data layer:** FastAPI endpoints, authentication/authorization logic, MQTT publishing/listening, and PostgreSQL tables initialized or updated through SQL migrations.
4. **Device and external services:** ESP32 firmware, MQTT broker, email service, Google identity verification, and optional Firebase Cloud Messaging.

The intended command flow is: user action → authenticated API request → ownership and request checks → MQTT publication → device response/status update where available → client display. The monitoring flow is: reading submission → threshold evaluation → alert/notification persistence → client retrieval. The exact hardware telemetry path must be verified against the deployed build.

### Functional Requirements

| ID | Requirement | Evidence to collect |
|---|---|---|
| FR-01 | A user can register/sign in through configured authentication options. | Successful and rejected authentication cases |
| FR-02 | An authenticated user can view and manage their registered devices. | Add, view, update, delete cases and ownership checks |
| FR-03 | A user can request a supported device control action. | API response and broker/device observation |
| FR-04 | A user can view logs and notifications and perform supported read/clear actions. | Before/after records and UI observations |
| FR-05 | A user can configure supported preferences and sensor thresholds. | Stored values and validation cases |
| FR-06 | The system can create or resolve an alert based on an evaluated reading. | In-range/out-of-range test cases using the supported input route |
| FR-07 | Optional external capabilities operate when their services and secrets are configured. | Separate configuration and integration tests |

### Non-Functional Requirements

The evaluation should define measurable criteria for usability, response time, reliability, security, and compatibility. Record the target platform and test conditions for each measure. Do not describe these qualities as achieved until supported by test evidence.

## Chapter 3. Methodology

### Research and Development Method

This project follows a software development and evaluation approach. The actual lifecycle used by the team should be named here (for example, iterative development) and supported by development records. The work can be documented through requirements analysis, system design, implementation, integration, and evaluation stages.

### Development Environment

The repository identifies Flutter/Dart for the client; Python, FastAPI, and Uvicorn for the API; PostgreSQL for persistent storage; MQTT for messaging; and ESP32 firmware materials for hardware integration. Complete this table with the versions and actual equipment used during evaluation.

| Item | Project evidence / value to verify |
|---|---|
| Flutter and Dart versions | [Record `flutter --version` and Dart version] |
| Python version and dependencies | [Record Python version and installed requirements] |
| Database | PostgreSQL; [version and hosting arrangement] |
| MQTT broker | [Broker type, deployment, TLS setting; do not include secrets] |
| Hardware | ESP32 board and sensors/actuators actually tested: [details] |
| Client platform | [Android/iOS/web/desktop and device/browser versions] |
| Network and test location | [Non-sensitive test setup] |

### System Implementation

The Flutter client groups interface screens under `lib/screens` and service code under `lib/services`. The API implementation is in `backend/app/main.py`, with database changes represented by SQL files in `backend/migrations`. The backend supports account and settings operations, device operations, MQTT control, logs, and notifications. Threshold and sensor behavior should be described only for routes and flows verified in the tested revision. Configuration-dependent services must be reported as enabled or disabled during evaluation.

### Evaluation Procedure

Use a test matrix with one row per requirement. For each case, record setup, action, expected result, observed result, pass/fail, and evidence reference. Separate API-level checks from user-interface checks and physical-device checks. For the alert feature, include readings below, within, and above the configured limits, and verify the alert lifecycle. For device control, record whether the command was merely accepted by the API, published to the broker, and physically observed by the device; these are different outcomes.

If the school requires a usability survey, identify the approved questionnaire, respondent inclusion criteria, recruitment process, consent procedure, scoring method, and number of respondents. Insert those details only after the protocol is approved and data is collected.

### Data Analysis

Report functional results as counts and percentages using the actual test cases executed. Summarize survey responses only using the instrument's prescribed scoring method. Report response times with the measurement method, sample count, and test conditions. Do not combine simulated/test readings with physical sensor readings without labeling them separately.

### Ethical and Security Considerations

Do not include real passwords, tokens, broker credentials, private keys, service-account JSON, or personally identifying respondent data in the paper or screenshots. Use test accounts and obtain required consent for human-participant evaluation. Describe access controls and configuration practices based on what was actually inspected and tested; avoid claiming a security certification.

## Chapter 4. Results and Discussion (Complete After Testing)

No results are supplied in this draft. Populate the tables from recorded evidence.

### Functional Test Results

| Requirement / test case | Cases run | Passed | Failed | Result (%) | Notes / evidence |
|---|---:|---:|---:|---:|---|
| Authentication | [ ] | [ ] | [ ] | [ ] | [ ] |
| Device management | [ ] | [ ] | [ ] | [ ] | [ ] |
| MQTT control | [ ] | [ ] | [ ] | [ ] | [ ] |
| Logs and notifications | [ ] | [ ] | [ ] | [ ] | [ ] |
| Threshold evaluation | [ ] | [ ] | [ ] | [ ] | [ ] |
| Physical sensor ingestion/history | [ ] | [ ] | [ ] | [ ] | State whether completed in tested revision |

### Usability / Performance Results

[Insert the approved instrument, respondent or sample description, measured results, analysis, and limitations. Include tables or figures only when supported by collected data.]

### Discussion

[Compare each observed result with the objective it addresses. Explain failures and configuration effects. Distinguish client display, API success, MQTT delivery, physical device response, and stored sensor history.]

## Chapter 5. Summary, Conclusions, and Recommendations (Complete After Testing)

### Summary

[Summarize the objectives, implemented components, evaluation method, and measured findings.]

### Conclusions

[Write one evidence-based conclusion for each objective. Do not claim successful real-time monitoring unless the physical sensing and end-to-end data path were tested.]

### Recommendations

Potential future work, subject to the tested state of the system:

1. Complete and validate authenticated ESP32 batch sensor ingestion and historical-reading retrieval.
2. Add end-to-end tests covering device ownership, command publication, device acknowledgement, and connection failures.
3. Evaluate alert behavior with repeatable in-range and out-of-range readings and document alert resolution.
4. Conduct a usability evaluation using the institution-approved instrument and representative participants.
5. Review authentication, credential storage, transport security, and deployment configuration before any production use.

## References (Verify and Format to the Required Style)

The following are implementation references, not a literature review. Add peer-reviewed and institution-required sources after confirming the required citation style and research scope.

- Flutter. (n.d.). *Flutter documentation*. https://docs.flutter.dev/
- FastAPI. (n.d.). *FastAPI documentation*. https://fastapi.tiangolo.com/
- PostgreSQL Global Development Group. (n.d.). *PostgreSQL documentation*. https://www.postgresql.org/docs/
- OASIS. (2019). *MQTT Version 5.0*. https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html
- Espressif Systems. (n.d.). *ESP32 documentation*. https://docs.espressif.com/projects/esp-idf/en/stable/esp32/

## Appendices to Prepare

- Appendix A: Approved requirements and test cases
- Appendix B: System architecture and data-flow diagrams
- Appendix C: User interface screenshots from the tested build
- Appendix D: Test logs and anonymized evaluation results
- Appendix E: Survey instrument and consent documents, if applicable
- Appendix F: Hardware schematic, bill of materials, and firmware configuration with secrets removed
