# Native action coverage audit — 2026-10-22

Current app b36c677 was tested against the actual mounted native screens, using the existing full catalog PL/EN examples and real local database. Result: **38 passed, 38 skipped**, zero failures. Skipped targets have no field-bearing example in this fixture; they are not proved to lack all assistant capabilities and are not counted as passed. Some have read-only queries, record confirmation or ISO-specific suites elsewhere.

This test checks field names and application of eligible read-only calculator examples through the current route handle. It also checks no unintended financial record creation. It does not prove every action, arbitrary language, voice hardware or real AI execution.

Verified targets: bevel, elbow_takeouts, elbow_cut, elbow_rotation, insert, reducer, mitre_bend, tube_bending, pipe_route, rolling_offset, pipe_slope, slope_cut, thermal_expansion, dn_mm, wall_thickness, pipe_weight, steel_weight, sanitary_tube, unit_converter, glossary, bolt_torque, shade, tungsten, filler_selector, heat_input, welder_calculators, power_source, cooling_time, weld_defects, hardness, hot_work, confined_space, fume, rigging, grinding, electrode_exposure, iso5817, weld_quotes.

Targets needing separate evidence: cut_list, iso_notebook, iso_scanner, component_library, spool_check, cone_layout, saddle_cut, saddle_template, pipe_supports, flange_check, bolt_kit, welder_pipes, welder_tanks, orbital_tig, assistant, pwht_planner, fillet_strength, pass_plan, distortion, pre_weld_checklist, interpass, weather_check, ndt_plan, ferrite_pmi, weld_journal, welder_exam, qualification_range, welder_certificates, wps_library, work_progress, weld_symbols, instruments, coupon_log, hydrotest, heat_tint, passivation, hourly_rate, piecework.

## Next concrete implementation

cone_layout is a substantive missing control connection: ConeLayoutPage has an existing native domain engine and editable fields, but no ToolHandleHost, supportedFields or assistant field-bearing skill. Add the actual handle and a strict cone development skill, sharing the existing domain engine. Start with the concentric height-defined cone, with explicit diameter reference and thickness (never infer those from a model), then cover eccentric and transition modes. Validate the complete proposed payload before any UI mutation. Retain current input units and do not silently reinterpret inches as millimetres. Prove mounted screen values and generated results, source-number preservation, invalid-payload atomicity and hidden-route rejection. Do not advertise unsupported shape modes as implemented.

Existing saddle modules also lack field-bearing catalog evidence and require source inspection before assigning their exact scope. Copy/clear currently advertises only its eight connected fitter calculators; no expansion was made during this audit.

## Runtime blocker revalidated

2026-10-22T05:18:13Z: local Railway CLI remains unauthorized; an empty invalid assistant POST still returns 404. Available browser is signed out at Railway; GitHub continuation also requires sign-in. No login credentials entered, no new device code, deployment or paid AI request. Browser returned to Railway activation for the pending user handoff. Updated report: outputs/fwp-runtime-recheck-native-audit-20261022.json in the chat workspace.

App registration version 6 still requires the backend update before a new APK is distributed. Latest delivered APK remains 5806c1e. Backend PR10 is not claimed merged or deployed. Full assistant goal remains active.
