# Preheat help correction — 2026-11-02

Scope: `preheat-temperature` in `lib/data/help_entries.dart`, PL and EN. This entry is also available to offline assistant help search.

The previous entry assigned fixed temperatures from CE bands and stated that CE above 0.55 mandates PWHT. It also called 200–300°C universally mandatory for P91. Replaced those rules with the actual selection factors and an explicitly attributed manufacturer example. This does not establish a project WPS or audit the whole knowledge base.

Evidence inspected:

- [TWI, Job Knowledge 046](https://www.twi-global.com/technical-knowledge/job-knowledge/defects-hydrogen-cracks-in-steels-prevention-and-best-practice-046): composition, thickness, joint, hydrogen, heat input and restraint affect cracking prevention; the EN 1011-2 guidance discussed concerns carbon/C-Mn steels.
- [ESAB, Guidelines for Welding CrMo, February 2023](https://esab.com/sites/nam_en/assets/ESAB%20University/GuidelinesForWeldingCrMo-022023.pdf), printed page 12: IIW CE method is not valid for the CrMo grades discussed. The page was also requested as a web screenshot; the table is not used as the numeric basis of the revised help entry.
- [Böhler Welding, Welding Solutions for Grade 91, 2021](https://cdnstorevoestalpine.blob.core.windows.net/image-container/812658/original/BW_Grade_91_EN_2021_GL_135_Preview.pdf), printed pages 8–9: general 200°C recommendation, ≥150°C accepted for thin GTAW components, interpass limited to 350°C. This exception is attributed guidance, not authorization to reduce a specified preheat.

Validation: 149 automated tests across help entries, knowledge questions and knowledge conversation passed, including PL/EN numeric parity and offline help search. These tests check application behavior and data consistency; the technical assessment rests on the sources above.

Remaining scope: backend `data/piping_knowledge.md` contains separate P22/preheat guidance (around section 12369) and other material-specific claims. They were located but not changed or verified by this help-entry correction. No assertion that all AI knowledge is now corrected.


Backend follow-up (2026-11-02): `6c9045b` corrects the corresponding preheat/interpass block in `backend/data/piping_knowledge.md`. P91 guidance is explicitly attributed to Böhler; the unqualified P22 thresholds and fixed heating width were removed. ESAB's printed pages 9 and 12 give inconsistent thin-P22 figures, so no single compulsory P22 temperature is inferred from them. Full backend tests: 524 passed; a retrieval check finds the corrected scope in the actual top-four results for a P91/P22 preheat query. Adjacent heat-input, cooling and PWHT claims remain outside this correction and need their own review.


Cooling follow-up (2026-11-02): backend `c246835` scopes the separate P91 cooling and DHT paragraphs to the component conditions in Böhler's printed page 9 and distinguishes DHT from PWHT. Full backend suite: 525 passed, including a top-four retrieval check for the scoped cooling paragraph. PWHT parameters, heat-input and other claims elsewhere in the section remain outside this correction; no paid live model answer was tested in this change.
