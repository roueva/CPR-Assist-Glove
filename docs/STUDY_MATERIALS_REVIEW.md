# Study Materials Review — vs. Approved Ethics Protocol ΕΗΔΕ 99737/2026

Read-only review. No files were edited. Scope: the materials in
`Thesis/Code_thesis/3 Validation/3. User Testing/_User Testing` (the folder the
review was scoped to), cross-checked against sibling folders in
`3. User Testing/` (`Protocol/`, `1 Informed Consent/`, `2 Demographics/`,
`3 SUS/`, `4 Interview/`, `5 Retention/`) and against the app/backend source
(`CPR-Assist-Server/routes/session.js`, `session_detail.dart`).

**On the approval document itself:** I could not locate a signed decision
letter from the ΕΗΔΕ bearing the reference "99737/2026" — no file with that
number in its name or a scanned decision exists anywhere under
`Thesis/Code_thesis`. What I *did* find is the submission package presumably
sent to the committee (`Protocol/CPR_Assist_ΑΙΤΗΣΗ.docx` application,
`Protocol/CPR_Assist_ΔΗΛΩΣΗ-ΕΥ-1.docx` supervisor declaration, and two research
protocol documents — see §1), plus one consent-form variant
(`1 Informed Consent/CPR_Assist_Έντυπο Ενημερωμένης συγκατάθεσης.docx` and
`Informed_Consent_EN.docx`) that itself states in its own body: *"Αριθμός
πρωτοκόλλου της εγκριτικής απόφασης: 99737/2026"* / "The protocol number of
the approving decision is 99737/2026." That sentence is the only evidence in
the materials that this number refers to an actual granted approval, and it
appears only in that one consent-form variant — not in the version actually
sitting in `_User Testing/`. Everything below treats **the research protocol
document as the approved reference** per the task's framing, but this
provenance gap should be resolved before the finding below on consent-form
versioning is dismissed as cosmetic.

---

## 1. Consent form vs. approved protocol

**Two different "approved protocol" documents exist, and they disagree with each other.**

`Protocol/CPR_Assist_Study Protocol.docx` (English) and
`Protocol/CPR_Assist_Greek Study Protocol.docx` describe the same study but
differ materially:

| Item | English protocol | Greek protocol |
|---|---|---|
| Sample size | "35 healthy adults... at least 40% women" | not stated in the document |
| Day 8 session | Presented as standard ("participants are invited to return") | Explicitly labelled **Προαιρετική** (optional), for "όσοι... μπορούν και επιθυμούν" |
| Extra Day-1 session | Not mentioned | Describes an **additional optional 5-minute session with active feedback** on Day 1 to test "διατήρηση της ποιότητας... κατά παρατεταμένη χρήση" (sustained-use quality) — this session appears in **no other document** (not in `Steps.txt`, not in the consent form, not in `README.md`, not in any of the five `_User Testing` instruments) |
| Questionnaire delivery | "self-reported data collected via Google Forms on a study device" | "Τα έντυπα ερωτηματολόγια ψηφιοποιούνται εντός 24 ωρών" (paper forms, digitised within 24h) |
| Pseudonymisation key | Not described | A **separate paper document** links participant code (P01...) to session ID, stored apart from electronic data |
| Data retention | "anonymised following study termination" (no date) | **5 years after thesis submission**, then permanently deleted |
| Legal framework cited | Not cited | GDPR 2016/679, Declaration of Helsinki, European Code of Conduct for Research Integrity (2017) |

**Severity: blocking.** I cannot tell which of these two documents — if either
— is the one actually reviewed and approved under 99737/2026, and the actual
study materials in `_User Testing/` don't match either one cleanly (see below).
An MSc thesis appendix or defence committee should not have to guess which
protocol was approved.

**Consent form: three different versions of the same filename.**

`1 Informed Consent/CPR_Assist_Έντυπο Ενημερωμένης συγκατάθεσης.docx` and
`_User Testing/CPR_Assist_Έντυπο Ενημερωμένης συγκατάθεσης.pdf` share the exact
same filename but different content:

| Field | `1 Informed Consent/....docx` (and `Informed_Consent_EN.docx`) | `_User Testing/....pdf` (the version in the reviewed folder) |
|---|---|---|
| Scientific lead named | Επίκ. Καθ. **Αλκίνοος Αθανασίου** / Assist. Prof. Alkinoos Athanasiou, `athalkinoos@auth.gr` | Καθ. **Παναγιώτης Δ. Μπαμίδης** / Prof. Panagiotis Bamidis, `bamidis@auth.gr` |
| ΕΗΔΕ approval number quoted | **"Αριθμός πρωτοκόλλου της εγκριτικής απόφασης: 99737/2026"** | Not present — only "έχει λάβει έγκριση" with no number |
| Consent/data retention window | "ανωνυμοποιηθούν έξι μήνες μετά την ολοκλήρωση της μελέτης" (6 months); consent valid "για 6 μήνες" | "θα διατηρηθούν μέχρι την 31 Δεκεμβρίου 2026" (fixed calendar date); consent valid "μέχρι 31 Δεκεμβρίου 2026" |
| Withdrawal contact email | `athalkinoos@auth.gr` | `bamidis@auth.gr` |

The scientific lead named in `Protocol/CPR_Assist_ΑΙΤΗΣΗ.docx` and
`ΔΗΛΩΣΗ-ΕΥ-1.docx` (the actual ethics filing documents, both naming Athanasiou
as supervisor) matches the `1 Informed Consent/` version, not the version
that is actually in `_User Testing/`. **Severity: blocking.** The document a
participant would actually sign is the one in `_User Testing/`, and it is the
one that (a) doesn't cite the approval number, (b) doesn't name the same
scientific lead as the ethics filing, and (c) states a different retention
policy than either protocol document. This looks like an older/reverted draft
was carried into the working folder instead of the finalised, ΕΗΔΕ-linked
version. I'm not fixing it — flagging it for you to confirm which file is
current.

**Language coverage gap.** The Greek protocol's inclusion criteria allow
"Ικανότητα κατανόησης **ελληνικής ή αγγλικής**" (Greek OR English
comprehension), but `Informed_Consent_EN.docx` — the only file that contains
the full English information sheet (risks, data handling, retention, approval
number) — is **not** in `_User Testing/`. The file actually there,
`1 Consent.docx`, is bilingual but contains **only the declaration/signature
page**, not the informational content. An English-only-reading participant
signing from the `_User Testing/` folder would be asked to declare "I have
been sufficiently and clearly informed about X, Y, Z" without ever having
received X, Y, Z in a language they read. **Severity: blocking** if any
participant is in fact English-speaking-only (permitted by the Greek
protocol's own inclusion criteria); should-fix at minimum since the two
protocol documents disagree on whether English is even allowed.

**Funding declaration without funding content.** Both consent variants have
the participant declare "I have been sufficiently and clearly informed about
the manner and sources of funding of the research," but no document in the
information sheet actually states a funding source. This may have been
covered verbally — I can't verify that from the materials, so I'm not
inferring it either way. Severity: minor.

---

## 2. Data fields vs. consent language

Pulled directly from `CPR-Assist-Server/routes/session.js` (the `cpr_sessions`
INSERT and the four sub-tables) and `session_detail.dart`
(`SessionDetail.toJson()`), not from `SIGNALS.md` or any doc.

**What the consent form tells participants is collected** (from
`_User Testing/....pdf`, section "Δεδομένα"):
> α) δημογραφικά στοιχεία (ηλικία, φύλο, επίπεδο εκπαίδευσης σε ΚΑΡΠΑ)
> β) μετρήσεις απόδοσης θωρακικών συμπιέσεων σε πραγματικό χρόνο μέσω του
> γαντιού (βάθος, ρυθμός, ποιότητα αποσυμπίεσης)
> γ) απαντήσεις σε ερωτηματολόγια αξιολόγησης χρηστικότητας (SUS)

i.e.: age, gender, CPR-training level; compression depth, rate, recoil
quality; SUS answers. Nothing else.

**What the system actually records per session**, per `session.js` /
`session_detail.dart`:

- **Compression biomechanics** (`session_compressions`, per-compression):
  depth, frequency, instantaneous rate, force, recoil, over-force, posture_ok,
  leaning, **wrist alignment angle, wrist flexion angle, compression axis
  deviation** (posture/wrist-motion data — not mentioned to participants at
  all, and not reducible to "depth, rate, recoil" as worded in the consent),
  effective depth, peak force, downstroke time, valley depth/timestamp.
- **Ventilation events**: timing, cycle number, duration, compliance.
- **Pulse-check events** (`session_pulse_checks`): classification, detected
  BPM, confidence, perfusion index, detector counts, user decision,
  **`patient_spo2`**, and **raw `ppg_samples`** (the photoplethysmography
  waveform itself, stored as JSON) — this is manikin/simulated "patient" data
  in this study context, not the rescuer, but it is still raw biosignal data
  the consent form never mentions.
- **Rescuer vitals — continuous stream** (`session_rescuer_vitals`, one row
  per sampling interval for the whole session): **heart_rate, spo2, rmssd
  (heart-rate variability), rescuer_pi (perfusion index), temperature,
  fatigue_score, signal_quality, pause_type, humidity**.
- **Rescuer vitals — session-level snapshots** on `cpr_sessions`:
  `user_heart_rate`, `user_temperature`, `rescuer_hr_last_pause`,
  `rescuer_spo2_last_pause`, `rescuer_wrist_temp_start`,
  `rescuer_wrist_temp_end`.
- **Fatigue detection**: `fatigue_onset_index`, `fatigue_alert_timestamp_ms`,
  `fatigue_alert_score` — computed in `SessionDetail.computeFatigueScore()`
  directly from the rescuer's own HR trend (40% weight), RMSSD decline (35%),
  and depth trend (25%).
- **Free-text note field** (`note`, up to 500 chars) attachable to a session.
- Mode/scenario-change event logs, two-minute rescuer-swap alerts, wrist
  dropout latch.

**Finding — severity: blocking.** The consent form's data section names only
compression performance metrics, demographics, and SUS answers. It **never
mentions that the system continuously records the participant's own heart
rate, SpO2, heart-rate variability, and skin temperature**, or that a
derived "fatigue score" is computed from those signals. This is exactly the
category the task asked to flag: participants are very unlikely to expect
their own cardiovascular and thermal physiology to be monitored and stored
throughout a "CPR technique" study, and continuous HR/SpO2/HRV is
special-category health data under GDPR Art. 9. This isn't an incidental
byproduct — rescuer-vitals monitoring and the fatigue score are a designed,
described feature of the app (see `SessionDetail.computeFatigueScore`,
`fatigueOnsetIndex`, `rescuerSwapCount`), so it's collected on every session,
not just edge cases. Whether the exclusion criteria (known cardiac disease,
pacemaker) were written with this monitoring in mind is unclear from the
materials — if participants are being physiologically monitored during
supervised exertion, the ethics committee should have been told that
explicitly, and participants should be told what is measured and why.

**Secondary finding — should-fix.** The eligibility-screening answers
collected in `_User Testing/2 Demographics.docx` section Δ (current
injury — with free-text description if yes; pregnancy; cardiac
condition/pacemaker/respiratory condition) are themselves special-category
health data. The consent form's data-collection section doesn't mention that
these screening answers are retained as part of the research dataset (as opposed
to being used only to gate participation and then discarded). The protocol
documents don't clarify this either.

**Minor.** Wrist-motion/posture fields (`wrist_alignment_angle`,
`wrist_flexion_angle`, `compression_axis_dev`) and the free-text `note` field
are not covered by "β) μετρήσεις απόδοσης... (βάθος, ρυθμός, ποιότητα
αποσυμπίεσης)" as literally worded, though they're arguably within the
spirit of "compression performance measurements."

---

## 3. Question quality

Quoting the final instruments in `_User Testing/`.

- **Leading — `4 Interview.docx`, Q2**: *"Σας βοήθησε η ανατροφοδότηση κατά τη
  συνεδρία με ανατροφοδότηση; Γιατί ή γιατί όχι;"* / "Was the feedback helpful
  during the session with feedback? Why or why not?" — presupposes the
  feedback was helpful (asks "why" it was helpful as the primary framing,
  with "or why not" tacked on). A neutral form would ask "How would you
  describe the feedback during that session?" or similarly open. **Severity:
  should-fix** — this is the interview's central usability question, and its
  framing risks confirmation bias in exactly the outcome the thesis is built
  around.

- **Double-barrelled — `4 Interview.docx`, Q1**: *"Ήταν άνετο το γάντι στη
  χρήση; Νιώσατε κάποια δυσφορία όσο το χρησιμοποιούσατε;"* / "Was the glove
  comfortable to wear? Did you feel any discomfort while using it?" — two
  distinct questions (comfort of fit vs. presence of discomfort) posed as one
  item with one set of probes. A participant could find the fit comfortable
  yet still report incidental discomfort (e.g., heat), and the instrument has
  no way to record a split answer other than free text. **Severity: minor** —
  the follow-up checkbox ("Main comfort issue: none / fit / weight /
  heat/sweat / restricted movement / other") partially recovers this, but the
  open question itself remains double-barrelled.

- **Double-barrelled — `4 Interview.docx`, Q7**: *"Θα χρησιμοποιούσατε αυτό το
  γάντι σε πραγματική έκτακτη ανάγκη; Γιατί; Και πιστεύετε ότι θα ήταν χρήσιμο
  για την εκπαίδευση στην ΚΑΡΠΑ;"* / "Would you use this glove in a real
  emergency? Why? And do you think it would be useful for training people in
  CPR?" — conflates two separate constructs (personal emergency-use intent vs.
  general training utility) in one prompt, with a single 5-point response
  scale ("Σε έκτακτη ανάγκη: σίγουρα ναι ... σίγουρα όχι") that only captures
  the first half. **Severity: should-fix** — the training-utility half of the
  answer has no forced-choice anchor at all, so it will only surface if the
  participant happens to address it in free text.

- **Assumed premise — `5 Retention.docx`, item 1**: *"Αισθάνομαι ότι θυμάμαι τη
  σωστή τεχνική ΚΑΡΠΑ."* / "I feel I remember the correct CPR technique." —
  phrased as agree/disagree on a positive assertion rather than as a neutral
  "How well do you feel you remember the CPR technique?" This is a minor
  version of acquiescence bias but consistent with the SUS-style item format
  used elsewhere, so I'd call it **minor**, not blocking.

- Not leading, for contrast: `2 Demographics.docx` and the SUS instrument
  (`3 SUS.docx`) are neutrally worded throughout — SUS items alternate
  positive/negative framing by design (see §4).

---

## 4. Scale consistency

| Instrument | Points | Direction | Anchors |
|---|---|---|---|
| Demographics Q8 confidence | 1–5 | 1 = low → 5 = high | Καθόλου/Λίγο/Μέτρια/Αρκετά/Πολύ σίγουρος-η |
| SUS (`3 SUS.docx`) | 1–5 | 1 = Διαφωνώ πλήρως → 5 = Συμφωνώ πλήρως (standard SUS, alternating item polarity by design) | Strongly disagree → Strongly agree |
| Post-session confidence (`3 SUS.docx` §A) | 1–5 | same as demographics | identical wording to Demographics Q8 |
| Retention confidence + items 1–3 (`5 Retention.docx`) | 1–5 | items 1–3 use bare "1 ☐ \| 2 ☐ \| 3 ☐..." with **no anchor labels shown per point** — only the confidence question above them carries labels | confidence item: labelled; items 1–3: unlabelled numeric scale only |
| Interview forced-choice items (e.g. "In an emergency: definitely yes / probably yes / unsure / probably no / definitely no") | 5 | definitely-yes → definitely-no | verbal only, no numeric scale |
| Interview attitude/engagement (researcher-rated, `4 Interview.docx`) | Attitude: 5-point (Very positive → Very negative); Engagement: **4-point** (Very high / High / Neutral / Low) | — | — |

**Finding — should-fix.** `5 Retention.docx` items 1–3 ("I feel I remember the
correct technique," "I still believe the glove would be useful," "I would
recommend this system") are presented as bare `1 ☐ | 2 ☐ | 3 ☐ | 4 ☐ | 5 ☐`
with no anchor text under each number, unlike every other 1–5 scale in the
battery (which all spell out "Not at all... Very" or "Strongly disagree...
Strongly agree" at minimum on first use). Respondents have to infer polarity
and label meaning from the confidence question above, which uses different
anchor wording ("Καθόλου σίγουρος-η...Πολύ σίγουρος-η") than would fit a
"remember / believe / recommend" agreement item. This is a real
data-cleaning risk exactly as flagged in the task brief.

**Finding — minor.** The researcher-completed "Attitude" scale is 5-point but
"Engagement" is 4-point (`4 Interview.docx`, end of form) — likely intentional
(no natural "neutral-low" midpoint issue) but worth a note since it's the one
scale-length inconsistency in an otherwise uniform 5-point battery.

**Not a defect:** SUS's alternating positive/negative item polarity (items 2,
4, 6, 8, 10 reverse-scored) is standard SUS methodology, and `README.md`
confirms scoring will handle it correctly ("odd items −1, even items 5−score,
sum ×2.5").

---

## 5. Demographic completeness

Fields collected in `_User Testing/2 Demographics.docx` (identical to
`2 Demographics/Demographics_Eligibility_Bilingual.docx`):

| Field | Stated analytical use? |
|---|---|
| Age | Yes — protocol groups/describes sample by age (Table 4.1-style demographics summary per `README.md`) |
| Gender | Yes — protocol requires "at least 40% women," reported in sample description |
| Dominant hand | No explicit use stated anywhere (not referenced in the protocol's analysis section, not used as a grouping variable in `cpr_analysis.py`'s described outputs per `README.md`) |
| Formal CPR training (yes/no) | Yes — protocol groups participants by "no prior training / lapsed / current" for baseline-performance comparison |
| Training recency | Yes — same grouping variable |
| Training type (theoretical/basic practical/healthcare/other) | Partially — feeds `training_type` column per `README.md`, but the protocol's stated analysis only describes grouping by recency/training-status, not training *type* |
| Medical/healthcare background (yes/no + free text) | **Not explained** — collected (`medical_background` column exists in `README.md`'s template) but neither protocol document nor the interview/analysis plan states what this variable is used for |
| Pre-session confidence (1–5) | Yes — explicit pre/post/day-8 comparison is the protocol's stated confidence analysis |
| Injury / pregnancy / cardiac condition (Δ, eligibility) | Yes, but only as **exclusion gates** — see §2's finding that their retention as *data* (vs. a pass/fail gate) isn't addressed |

**Finding — minor/should-fix.** "Dominant hand" and "medical/healthcare
background" are collected without a stated analytical purpose anywhere in the
protocol, README, or interview guide. Dominant hand plausibly matters (glove
is worn on one hand — handedness could confound depth/force readings), but
that rationale isn't written down anywhere in the materials I reviewed, so I
can't confirm it's an intentional covariate rather than reflexive
demographic boilerplate. Per data-minimisation, either state the purpose or
drop the field.

**Sufficiency for publication.** Age, gender, and CPR-training history are
adequate to characterise the sample against the protocol's own inclusion
criteria (18–65, ≥40% women, no CPR experience required) and to support the
planned training-status subgroup analysis. No occupation, education level, or
health-literacy proxy is collected — likely fine for a device-usability study
of this scope, but worth an explicit note in the limitations section if the
thesis makes any claim about generalisability beyond "lay adults."

---

## 6. Withdrawal and data retention

**Withdrawal mechanism — present, but the "how" conflicts across documents.**
The version in `_User Testing/....pdf` says: *"Η συγκατάθεση δίνεται μέχρι 31
Δεκεμβρίου 2026 ή μέχρι να ανακληθεί στέλνοντας ένα ηλεκτρονικό μήνυμα στο
bamidis@auth.gr ή συμπληρώνοντας την αίτηση που βρίσκεται στο τέλος του
εντύπου."* A withdrawal-request template *is* included in the same PDF
(Section III, "ΑΝΑΚΛΗΣΗ ΣΥΓΚΑΤΑΘΕΣΗΣ ΣΥΜΜΕΤΕΧΟΝΤΑ"), so the mechanism itself is
adequately documented. But the contact address quoted (`bamidis@auth.gr`)
belongs to the scientific lead named in *that* document — which, per §1, is
not the same person named in the actual ethics-filing paperwork
(`athalkinoos@auth.gr`). A participant following the instructions in the
`_User Testing/` PDF would email a different person than the one who
supervised the approved research protocol.

**What happens to already-collected data on withdrawal — stated, and
internally consistent within the PDF**: *"Σε περίπτωση που ανακαλέσετε την
συγκατάθεσή σας, θα διαγραφούν όλα τα δεδομένα που συλλέξαμε. Το δικαίωμα να
ανακαλέσετε... δεν επηρεάζει τη νομιμότητα της επεξεργασίας... πριν την
ανάκληση."* — full deletion on withdrawal, with the standard GDPR carve-out
that processing before withdrawal remains lawful. This is fine as far as it
goes, and matches the Greek protocol's data-lifecycle in spirit (deletion
rather than indefinite retention).

**Retention period — three different answers, see also §1:**
- `_User Testing/....pdf` (the version participants actually see): retained
  until **31 December 2026**, then anonymised.
- `1 Informed Consent/....docx` + `Informed_Consent_EN.docx`: anonymised
  **6 months after study completion** (a floating date, not a fixed one).
- `Protocol/CPR_Assist_Greek Study Protocol.docx`: retained for **5 years
  after thesis submission**, then **permanently deleted** (not anonymised —
  a materially different end-state than "anonymised").

**Severity: blocking.** These aren't rounding differences — "31 Dec 2026,"
"six months after completion," and "five years after thesis submission" can
easily resolve to dates years apart, and "anonymised" vs. "permanently
deleted" are different data-handling outcomes with different downstream
implications (anonymised data can still be analysed/retained in some form;
deleted data cannot). A participant reading the consent form has no way to
know which of these three commitments actually governs their data, and
neither do I from the materials alone — I'd flag this as the single most
important item to resolve before any further participants are enrolled,
since it directly affects what the consent form promises versus what the
approved protocol (whichever version that is) permits.

---

## Summary of blocking items

1. Two approved-protocol documents (EN/GR) disagree on sample size framing,
   an entire extra optional session, Day-8 mandatory-vs-optional status,
   questionnaire delivery method, and retention policy (§1).
2. The consent form actually placed in `_User Testing/` names a different
   scientific lead and omits the ΕΗΔΕ approval number found in a
   same-named file elsewhere in the tree (§1).
3. Continuous rescuer heart rate, SpO2, HRV, and skin temperature — and a
   derived fatigue score — are recorded every session but never disclosed in
   the consent form's data-collection section (§2).
4. Non-Greek-reading participants (permitted under the Greek protocol's own
   inclusion criteria) have no access to the full information sheet in
   `_User Testing/` — only a bilingual signature page (§1).
5. Three mutually inconsistent data-retention commitments exist across the
   consent form and the two protocol documents (§6).
