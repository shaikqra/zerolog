# App Store readiness — ZeroLog (pre-submission research)

**All Apple sources checked live on 2026-10-29.** Re-check before every submission;
the App Review Guidelines are a living document and Apple restates that explicitly.

Primary sources:
- App Review Guidelines — https://developer.apple.com/app-store/review/guidelines/ (checked 2026-10-29)
- Privacy manifest files — https://developer.apple.com/documentation/bundleresources/privacy-manifest-files (checked 2026-10-29)
- Describing use of required reason API — https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api (checked 2026-10-29)
- NSPrivacyAccessedAPIType / ...Reasons — https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype (checked 2026-10-29)
- App Privacy Details (nutrition labels) — https://developer.apple.com/app-store/app-privacy-details/ (checked 2026-10-29)
- Setting up HealthKit / Authorizing access to health data — https://developer.apple.com/documentation/healthkit/setting-up-healthkit (checked 2026-10-29)
- Requesting access to protected resources — https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources (checked 2026-10-29)
- Third-party SDK requirements — https://developer.apple.com/support/third-party-SDK-requirements/ (checked 2026-10-29)
- Auto-renewable subscriptions — https://developer.apple.com/app-store/subscriptions/ (checked 2026-10-29)
- Small Business Program — https://developer.apple.com/app-store/small-business-program/ (checked 2026-10-29)

---

## 0. The finding that changes the architecture

**Guideline 5.1.3(ii), verbatim:** "Apps must not write false or inaccurate data into
HealthKit or any other medical research or health management apps, and **may not store
personal health information in iCloud**."

`references/stack.md` currently chooses **SwiftData + CloudKit** specifically because it
"keeps health data in the user's own iCloud." That is the one storage location Guideline
5.1.3(ii) names. This must be resolved **before the data layer is built**, not at
submission. Options to evaluate:

1. Keep HealthKit-derived values (HRV, sleep, resting HR, bodyweight, height, DOB,
   biological sex) **on-device only**, never in the CloudKit container; sync only
   app-authored training data (sets, reps, weights, dates).
2. Local-only persistence with no CloudKit for any health-adjacent entity.
3. Own backend with explicit consent (loses the "shrinks the GDPR surface" benefit that
   justified CloudKit in the first place, and adds cost).

Note the ambiguity worth deciding deliberately: workout logs the app authors itself are
arguably not "personal health information" read from Health, but HRV/sleep/resting HR/
bodyweight plainly are. Design so the boundary is explicit in the schema.

---

## 1. Guidelines that govern this app

### Health, fitness and HealthKit

| # | What it says and why it binds ZeroLog |
|---|---|
| **5.1.3(i)** | "Apps may not use or disclose to third parties data gathered in the health, fitness, and medical research context—including from the Clinical Health Records API, HealthKit API, **Motion and Fitness**, MovementDisorder APIs, or health-related human subject research—for advertising, marketing, or other use-based data mining purposes other than improving health management, or for the purpose of health research, and then only with permission." Also: "**You must disclose the specific health data that you are collecting from the device.**" Note it covers Motion and Fitness, so the IMU rep-detection stream is in scope, not just HealthKit reads. |
| **5.1.3(ii)** | No false/inaccurate writes to HealthKit; **no personal health information in iCloud**. See §0. |
| **5.1.3(iii)/(iv)** | Human-subject research consent + independent ethics board approval. The Phase 0 gym data collection is internal, not a published study — but if labelled IMU data is ever collected from third-party volunteers and published or used as a research claim, these apply. |
| **5.1.2(vi)** | "Data gathered from the HomeKit API, **HealthKit**, Clinical Health Records API, MovementDisorder APIs, ClassKit or from depth and/or facial mapping tools ... **may not be used for marketing, advertising or use-based data mining, including by third parties.**" This is the explicit "no advertising, no sale/sharing to third parties" rule. |
| **2.5.18** | Ads "may not engage in targeted or behavioral advertising based on sensitive user data such as health/medical data (**such as from the HealthKit APIs**)". |
| **2.5.1** | "HealthKit should be used for health and fitness purposes and **integrate with the Health app**." Enabling the entitlement without meaningful, visible use is a rejection. |
| **1.4.1** | Medical apps reviewed with greater scrutiny. "Apps must clearly disclose data and methodology to support accuracy claims relating to health measurements, and if the level of accuracy or methodology cannot be validated, we will reject your app." Also "Apps should remind users to check with a doctor." Both bite: (a) rep-count accuracy claims, (b) "your HRV is low, cut today's volume". |
| **1.6** | Data security — appropriate measures for the data handled. |
| **2.5.14** | "Apps must request explicit user consent and provide a clear visual and/or audible indication when **recording, logging, or otherwise making a record of user activity**." Continuous wrist IMU capture needs a visible in-session indicator, not silent background recording. |
| **2.5.4** | Background modes only for intended purposes — relevant to workout sessions and HealthKit background delivery. |

### Privacy, policy and consent

| # | Relevance |
|---|---|
| **5.1.1(i)** | Privacy policy mandatory — see §5. |
| **5.1.1(ii)** | Consent required for collection; "**Paid functionality must not be dependent on or require a user to grant access to this data.**" The subscription must work for a user who denies HealthKit and motion access. Must offer an easy way to withdraw consent. Purpose strings must "clearly and completely describe your use of the data". |
| **5.1.1(iii)** | Data minimisation — request only HealthKit types an actual shipped feature reads. Prefer the photo picker over full library access. |
| **5.1.1(iv)** | Respect permission settings; provide alternatives when denied (e.g. manual bodyweight entry if HealthKit is refused). |
| **5.1.1(v)** | If the app supports account creation, **account deletion must be offered in-app**. |
| **5.1.1(ix)** | "Apps that provide services in highly regulated fields (such as banking and financial services, **healthcare**, gambling, legal cannabis use, air travel and crypto exchanges) **or that require sensitive user information should be submitted by a legal entity** that provides the services, **and not by an individual developer.**" A solo Apple Developer Program individual account shipping HRV/sleep/bodyweight is exposed here. |
| **5.1.2(i)** | "You must clearly disclose where personal data will be shared with third parties, **including with third-party AI**, and obtain explicit permission before doing so." This is directly the food-photo vision API. |
| **5.1.2(ii)** | Data collected for one purpose may not be repurposed without further consent. |
| **5.1.2(iii)** | No surreptitious profile building. |

### Business, metadata, completeness

| # | Relevance |
|---|---|
| **3.1.1** | Unlocking features/subscriptions must use IAP. Settles the open item in `stack.md`: a $49.99 Stripe "founding member" pre-order that unlocks in-app value is not compliant. Restore mechanism required for restorable purchases. |
| **3.1.2 / 3.1.2(a)** | Auto-renewable subs: ongoing value, **minimum 7-day period**, "must work on all of the user's devices where the app is available" — iPhone **and** Apple Watch. |
| **3.1.2(b)** | Seamless upgrade/downgrade; users must not be able to accidentally hold two variants. |
| **3.1.2(c)** | "Before asking a customer to subscribe, you should clearly describe what the user will get for the price," per Schedule 2 of the Program License Agreement. |
| **2.1(a)/(b)** | Final build, working backend, demo account or approved demo mode, IAPs visible and functional to the reviewer. |
| **2.3.1 / 2.3.2 / 2.3.12** | Specific Notes for Review; screenshots/description must indicate what needs a subscription. |
| **2.3.6** | Honest age rating. |
| **4.2** | Minimum functionality. |

---

## 2. PrivacyInfo.xcprivacy requirements

**Enforcement:** since **1 May 2024**, App Store Connect rejects uploads that use a
required-reason API without describing the reason in the privacy manifest. This is an
*upload* failure, not a review note.

**Placement:** `PrivacyInfo.xcprivacy` at the root of the app bundle
(`ZeroLog.app/PrivacyInfo.xcprivacy`). The **watchOS app is a separate bundle** — if watch
code touches required-reason APIs or collects data, it needs its own declarations. A
third-party SDK cannot rely on the host app's manifest.

### Required-reason APIs this app is likely to call

| Category | Likely reason code | Why ZeroLog hits it |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` (app-only) and/or `1C8F.1` (App Group) | `@AppStorage`/`UserDefaults` for settings; `1C8F.1` if iPhone and Watch share an App Group. RevenueCat also uses it. |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `8FFB.1` if absolute timestamps are needed; `35F9.1` if only elapsed time | **The sharp edge for rep detection.** `CMLogItem.timestamp` is seconds since boot, so converting IMU samples to wall-clock dates means reading `systemUptime`/`mach_absolute_time()`. Under `35F9.1`, boot time and derived data **may not be sent off-device** (only elapsed-time info may). Under `8FFB.1`, in-app absolute event timestamps may be sent off-device but **the boot time itself may not**. Pick the code that matches what actually leaves the device. |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` (app/App Group/CloudKit container); `3B52.1` (user-picked files) | Reading creation/modification metadata of cached IMU session files or food-photo caches; `3B52.1` only for document-picker-granted files. |
| `NSPrivacyAccessedAPICategoryDiskSpace` | `E174.1` (check before write) | Only if the app checks free space before writing raw IMU buffers or photo caches. `85F4.1` only if space is *displayed* to the user. |
| `NSPrivacyAccessedAPICategoryActiveKeyboards` | — | Not applicable. Do not declare. |

Rule from Apple: declare reasons that "accurately reflect your use ... and the data derived
from their use", use the data only for declared reasons, keep them consistent with the app's
presented functionality, and never use them for tracking. Do not pick a broad code because
it is convenient. If a genuine use has no listed reason, request a new approved reason
rather than mis-declaring.

### Data-type declarations (`NSPrivacyCollectedDataTypes`)

One dict per collected type with `NSPrivacyCollectedDataType`,
`NSPrivacyCollectedDataTypeLinked`, `NSPrivacyCollectedDataTypeTracking`,
`NSPrivacyCollectedDataTypePurposes`. Set `NSPrivacyTracking` to `false` and leave
`NSPrivacyTrackingDomains` empty unless something genuinely tracks.

### Third-party SDKs

- Apple's mandatory "SDKs that require a privacy manifest and signature" list (checked
  2026-10-29) does **not** include RevenueCat, Sentry, PostHog or TelemetryDeck. The
  obligation still applies to any SDK that uses required-reason APIs.
- **RevenueCat ships a manifest** (verified against `purchases-ios/Sources/PrivacyInfo.xcprivacy`
  on 2026-10-29): declares `NSPrivacyAccessedAPICategoryUserDefaults` → `CA92.1`, and
  `NSPrivacyCollectedDataTypePurchaseHistory` as *not linked*, *not tracking*, purpose
  App Functionality. Manifest support landed in the iOS SDK at 4.40.0 — pin at or above that.
- Two reconciliation jobs: (a) RevenueCat's manifest does **not** declare
  `FileTimestamp`, though community analysis reported `creationDate` use in its receipt
  parsing — verify with the privacy report on the exact version pinned; (b) RevenueCat
  declares purchase history as *unlinked*, but if ZeroLog sets a RevenueCat App User ID
  tied to an account, ZeroLog's own nutrition label should reflect that it is linked.
- Generate **Product > Archive > Generate Privacy Report** and diff it against the
  nutrition-label answers before every submission.

---

## 3. Privacy nutrition labels for this exact data list

Apple's definition of "collect": transmitting data off-device and retaining it beyond what
is needed to service the request in real time. **On-device-only processing is not
"collected"** — which is the strongest argument for keeping raw IMU on device.

| Nutrition label type | ZeroLog items | Purposes | Linked? |
|---|---|---|---|
| **Health** (Health & Fitness) | HRV, sleep, resting heart rate, bodyweight, height, age/DOB, biological sex, fat-loss/maintain/build goal | App Functionality, Product Personalization | Yes if tied to an account/user ID |
| **Fitness** (Health & Fitness) | workout logs (exercise, weight, reps, dates), Apple Watch accelerometer/gyroscope motion, derived rep counts | App Functionality, Product Personalization | Yes if account-linked |
| **Photos or Videos** (User Content) | food photographs uploaded to the vision API | App Functionality | Depends on account linkage |
| **Purchase History** (Purchases) | subscription state via StoreKit/RevenueCat | App Functionality | Per RevenueCat: unlinked — reconcile with your own App User ID choice |
| **User ID** (Identifiers) | only if accounts exist | App Functionality | Yes |
| **Crash Data / Performance Data** (Diagnostics) | only if Sentry is added | App Functionality / Analytics | Usually unlinked |
| **Product Interaction** (Usage Data) | only if analytics is added | Analytics | Depends |

Notes:
- **Tracking must be answered "No"**, and no ATT prompt should ship. Apple rejects
  unnecessary ATT prompts, and health-based ad targeting is separately barred by 2.5.18.
- Biological sex is **not** in Apple's "Sensitive Info" bucket (that list is racial/ethnic,
  sexual orientation, pregnancy, disability, religious, union, political, genetic,
  biometric). Declare it under **Health**.
- 5.1.3(i) adds an obligation beyond the label: disclose the *specific* health data read.
- Food calorie/macro estimates returned by the vision model are derived health data —
  if stored server-side, they are collected.
- Labels can be updated in App Store Connect without an app update, and must be kept
  accurate as practices change.

---

## 4. Mandatory Info.plist usage-description strings

| Key | Needed for | Status |
|---|---|---|
| `NSHealthShareUsageDescription` | **Reading** HRV, sleep, resting HR, bodyweight, height, DOB, biological sex | **Required** |
| `NSHealthUpdateUsageDescription` | **Writing** workouts/bodyweight back to Health | Required if the app saves anything to HealthKit (recommended, and supports the 2.5.1 "integrate with the Health app" expectation) |
| `NSMotionUsageDescription` | CoreMotion accelerometer/gyroscope/`CMBatchedSensorManager` | **Required — on every target that touches motion, including the watchOS app** |
| `NSCameraUsageDescription` | capturing food photos | Required |
| `NSPhotoLibraryUsageDescription` | choosing an existing food photo | Required unless you use `PHPickerViewController`, which needs no permission and satisfies 5.1.1(iii) |
| `NSPhotoLibraryAddUsageDescription` | only if writing images back to the library | Probably not needed |
| `NSHealthClinicalHealthRecordsShareUsageDescription` | clinical records | **Not applicable — and do not tick the Clinical Health Records capability.** Apple: "App Review may reject apps that enable the Clinical Health Records capability if the app doesn't actually use the health record data." |
| `NSHealthRequiredReadAuthorizationTypeIdentifiers` | clinical record types only | Not applicable |
| `NSUserTrackingUsageDescription` | ATT | Should be **absent** |

Also: HealthKit capability / `com.apple.developer.healthkit` entitlement; Background
Delivery sub-capability only if `enableBackgroundDelivery` is used. Enabling HealthKit makes
Xcode add `healthkit` to `UIRequiredDeviceCapabilities` — remove it if HealthKit is optional,
or unsupported devices are silently excluded.

### What happens at runtime if one is missing

- **General (Apple, "Requesting access to protected resources"):** "Always provide a valid
  purpose string ... If you don't, **attempts to access the resource fail, and might cause
  your app to crash.**" Xcode detects the crash and reports the missing purpose string.
- **CoreMotion:** no purpose string → the app is terminated on first motion access. There
  is no `authorizationStatus` request API for raw accelerometer/gyro streams, so you also
  get no graceful denial path — ship the string and handle start/update handler errors.
- **HealthKit:** the failure is an error, not a crash. Apple's own sample comment:
  "Typically, authorization requests only fail if you haven't set the usage and share
  descriptions in your app's information property list, or if Health data isn't available
  on the current device." `requestAuthorization(toShare:read:)` throws.
- **At review, independent of runtime:** "App Review checks for the use of protected
  resources, and **rejects apps that contain code accessing those resources without a
  purpose string**" — merely linking code that touches the API is enough.
- Purpose strings must be non-blank, under 4,000 bytes, correctly typed, and "accurate,
  meaningful, and specific". Localise via an `InfoPlist.xcstrings` string catalog; the
  requirements apply to every localisation. Since the app targets US **and UK**, English
  only is fine, but any added locale must carry translated strings.

---

## 5. Is a published privacy policy mandatory?

**Yes — unconditionally.** Guideline 5.1.1(i): "All apps must include a link to their
privacy policy **in the App Store Connect metadata field and within the app in an easily
accessible manner**." The App Privacy Details page repeats that the Privacy Policy URL is
required (a Privacy Choices URL is optional but useful for deletion/access requests).

It must "clearly and explicitly":
1. Identify **what** data the app/service collects, **how** it collects it, and **all uses**.
2. Confirm that any third party the app shares user data with — "analytics tools,
   advertising networks and third-party SDKs, as well as any parent, subsidiary or other
   related entities" — "will provide the same or equal protection of user data as stated in
   the app's privacy policy and required by these Guidelines." For ZeroLog this names the
   **vision model vendor**, the proxy host, RevenueCat, and later Sentry/analytics.
3. Explain **data retention/deletion** policies and describe **how a user can revoke
   consent and/or request deletion** of their data.

Add, from adjacent guidelines: the **specific health data** read from the device
(5.1.3(i)), and that food photographs are sent to a **third-party AI** service with
explicit permission (5.1.2(i)).

---

## 6. Subscriptions, free trials, and the Small Business Program

### Auto-renewing subscription rules
- **Must use StoreKit IAP** (3.1.1). No external purchase path that unlocks in-app value.
- **Minimum period 7 days**; must deliver **ongoing value**; must be **available across all
  the user's devices** where the app is available — so the entitlement must resolve on the
  Apple Watch app, not just the phone.
- **Before purchase**, show: what the subscriber gets, price, subscription duration/billing
  frequency, auto-renewal terms, trial length and the price after the trial ends, and how to
  cancel. Link Terms/EULA and the privacy policy from the paywall.
- **Restore purchases** must exist and work.
- Must not require extra tasks (social posts, contact uploads, check-ins) to get what was
  paid for; must not scam or bait-and-switch.
- Support upgrade/downgrade via subscription group **levels**; expose
  `showManageSubscriptions(in:)` so users can manage in-app.
- Handle Ask to Buy, deferred and interrupted purchases; verify entitlements with StoreKit 2
  or server-side.
- **Free trials:** for an auto-renewable subscription, use an **introductory offer**
  configured in App Store Connect. The "XX-day Trial" Non-Consumable at Price Tier 0 route
  described in 3.1.1 is for **non-subscription** apps only — do not mix them up. Customers
  can redeem one introductory offer per subscription group.
- Useful retention mechanics that are not blockers: billing grace period, win-back offers,
  offer codes.
- Revenue note: standard subscription commission drops so the developer receives **85% net
  revenue after one year** of paid service in a subscription group. Free trials and renewal
  extensions do **not** count toward days of paid service.

### Small Business Program — 15% commission eligibility
- **Benefit:** reduced **15%** commission on paid apps and Apple In-App Purchases.
- **Threshold:** no more than **1 million USD in total proceeds** (sales net of Apple's
  commission and certain taxes/adjustments) during the 12 fiscal months in the **previous
  calendar year**, and no more than 1M USD **in the current year**.
- **Developers new to the App Store qualify** — which is ZeroLog's position.
- **Associated Developer Accounts must be listed**; the >50% ownership or
  ultimate-decision-authority tests define them, and their proceeds are aggregated.
- **Enrolment is not automatic.** You must: be the **Account Holder** in the Apple Developer
  Program; review and accept the **latest Paid Apps agreement (Schedule 2)** in App Store
  Connect; list Associated Developer Accounts if any.
- **Timing:** proceeds adjust **15 days after the end of the fiscal month in which
  enrolment is approved** — so enrol before launch, not after first revenue.
- Cross the 1M threshold → standard rate applies to future sales. Fall back below →
  re-qualify the following calendar year.
- App transfers carry proceeds to every account that initiates or accepts the transfer.
- EU alternative terms + SBP → a further reduced **10%** for subscriptions after year one.
- Side benefit worth knowing: SBP members with fewer than two million first-time App Store
  downloads are eligible to use **Apple Foundation Models on Private Cloud Compute with no
  cloud API cost** (requires the PCC entitlement). That is a live alternative to paying a
  third-party vision vendor per call — and it would remove the "food photos go to a
  third-party AI" disclosure problem entirely. Worth a spike before committing to Gemini
  Flash / GPT-4o-mini.

---

## 7. Most common rejection reasons for health & fitness apps

Designed-out in advance, these are the recurring ones:

1. Vague purpose strings ("This app needs your health data") instead of naming the feature.
2. Over-requesting HealthKit types with no shipped feature reading them (5.1.1(iii)).
3. HealthKit entitlement enabled but barely used, or no Health app integration (2.5.1).
4. Clinical Health Records capability ticked but unused.
5. Gating paid or core functionality on granting HealthKit/motion permission (5.1.1(ii)).
6. Privacy policy URL present in App Store Connect but **not reachable inside the app**, or
   silent on retention, deletion, and consent withdrawal.
7. Nutrition labels that omit Health/Fitness, or disagree with the privacy manifest,
   the privacy policy, or observed network traffic.
8. No in-app account deletion when accounts exist (5.1.1(v)).
9. Unsubstantiated accuracy or medical claims — "medical grade", "measures your recovery",
   implied diagnosis — with no methodology disclosure and no "check with a doctor" reminder
   (1.4.1).
10. Reviewer cannot exercise watch-only features: no demo mode, no seeded data, no notes
    explaining that rep detection needs an Apple Watch on a wrist (2.1).
11. Backend offline during review — expired vision API key, exhausted quota, paused free
    tier (2.1).
12. Paywall missing price, duration, billing frequency, renewal terms, trial length or
    post-trial price; or no restore button (3.1.2(c), 3.1.1).
13. External purchase links or web checkout that unlock in-app content (3.1.1).
14. **Upload rejected by App Store Connect** for undeclared required-reason APIs.
15. Shipping an ATT prompt when nothing tracks.
16. Sending health or fitness data to analytics, attribution or ad SDKs (5.1.2(vi), 5.1.3(i)).
17. Storing health information in iCloud (5.1.3(ii)).
18. Sensitive-health app submitted by an individual rather than a legal entity (5.1.1(ix)).
19. Metadata/screenshots that imply diagnosis or treatment, or don't show subscription gating.
20. Missing required screenshot sets, or an archive below the current Xcode/SDK upload floor.

---

## 8. Prioritised checklist

### A. Hard blockers — resolve before submission (several before coding)

1. **Resolve the 5.1.3(ii) iCloud/health conflict** and re-decide the SwiftData+CloudKit
   plan. Architectural; do it before the data layer exists.
2. **`PrivacyInfo.xcprivacy`** in the app bundle (and the watch bundle if applicable) with
   every required-reason API declared, correct codes, verified by Xcode's privacy report.
   Undeclared = **upload rejection**.
3. **Decide and document the SystemBootTime reason code** (`8FFB.1` vs `35F9.1`) against
   what actually leaves the device, because the two codes have different off-device rules.
4. **All purpose strings present and specific:** `NSHealthShareUsageDescription`,
   `NSHealthUpdateUsageDescription` (if writing), `NSMotionUsageDescription` **on iPhone and
   watch targets**, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` (or use
   `PHPickerViewController`). Missing = crash or auth failure **and** rejection.
5. **Do not enable Clinical Health Records.**
6. **Privacy policy live, covering all three 5.1.1(i) points**, linked in App Store Connect
   **and** reachable in-app.
7. **Explicit consent screen before any food photo leaves the device**, naming the
   third-party AI processor (5.1.2(i)).
8. **Nutrition labels** declaring at minimum Health, Fitness, Photos or Videos, Purchase
   History; tracking answered **No**; reconciled against the manifest and real traffic.
9. **Zero health/fitness data to analytics, attribution or ads** (5.1.2(vi), 5.1.3(i),
   2.5.18). Settles the open PostHog-vs-TelemetryDeck item: whichever ships, no health data.
10. **StoreKit IAP only.** Kill the Stripe "founding member" pre-order that unlocks in-app
    value; use Apple's free App Store pre-orders instead.
11. **Paywall discloses** price, duration, billing frequency, renewal, trial length,
    post-trial price, cancellation; **restore purchases works**; entitlement resolves on the
    Watch (3.1.2(a)).
12. **App works with permissions denied** — HealthKit/motion refusal must not break paid
    functionality (5.1.1(ii)); offer manual bodyweight entry.
13. **Visible recording indicator + explicit consent** for continuous IMU capture (2.5.14).
14. **Accuracy and medical framing:** disclose rep-detection methodology and measured
    accuracy, avoid medical claims, add a "check with a doctor" reminder on the
    HRV-driven volume recommendation (1.4.1).
15. **Account deletion in-app** if accounts are introduced (5.1.1(v)).
16. **Legal entity vs individual developer** decision (5.1.1(ix)) — see lawyer questions.
17. **Reviewer access:** demo mode or seeded data for watch rep detection, live vision
    backend with quota, specific Notes for Review (2.1).
18. **Archive meets the current Xcode/SDK upload floor** and the current required screenshot
    sets — re-check Upcoming Requirements and the screenshot spec at submission time.
19. **Pin RevenueCat ≥ 4.40.0** (manifest shipped) and verify its manifest covers what the
    pinned version actually calls.

### B. Lower-priority cleanup

1. Enrol in the **Small Business Program** before launch (affects commission, not
   submission) and accept the latest Schedule 2.
2. Add an optional **Privacy Choices URL** for data access/deletion requests.
3. Localise purpose strings via `InfoPlist.xcstrings` if any locale beyond English ships.
4. Spike **Apple Foundation Models on Private Cloud Compute** as a third-party-AI-free food
   photo path (SBP + <2M downloads + PCC entitlement).
5. Remove `healthkit` from `UIRequiredDeviceCapabilities` if HealthKit is optional.
6. Subscription polish: billing grace period, win-back offers, offer codes,
   `showManageSubscriptions(in:)`, subscription group levels for upgrade/downgrade.
7. HIG pass: Dark Mode, Dynamic Type, NavigationStack, sheet dismiss controls, empty states.
8. Pre-submission runtime network audit (proxy the app, confirm nothing unexpected leaves).
9. Re-read the guidelines at submission — Apple restates that they change at any time.

---

## 9. Questions for a qualified lawyer

**Not legal advice. These are flagged as out-of-scope items requiring professional review —
no conclusion is offered on any of them.** Each names the specific ZeroLog data item that
triggers it.

1. **HRV, sleep and resting heart rate read from HealthKit, plus bodyweight, height, age and
   biological sex** — do these amount to "data concerning health" / special category data
   under UK GDPR Article 9, and if so what lawful basis, explicit-consent mechanics,
   Article 9 condition, and DPIA are required before launch in the UK?
2. **Apple Watch raw accelerometer and gyroscope streams** used to infer exercise — are
   continuous IMU data treated as health data or biometric data under UK GDPR and under US
   state law, given that the *purpose* is physiological inference?
3. **Food photographs sent to a third-party vision model API** — is that vendor a processor
   or an independent controller; what Article 28 data processing agreement is needed; is
   this an international transfer requiring a transfer mechanism if the vendor is US-based;
   and must the contract forbid using customer images for model training?
4. **US consumer health data laws** — does a US-available app handling HRV, sleep, resting
   heart rate, bodyweight and food/calorie data fall within Washington's My Health My Data
   Act (and comparable laws such as Nevada SB 370), and if so does it require a separate
   consumer health data privacy policy, separate consent for collection, and separate
   authorization for any sharing?
5. **The "your HRV is low, reduce today's training volume" feature** — does this risk
   classification as a medical device or clinical decision support under FDA, UK MHRA or EU
   MDR rules, or does it sit within a general wellness exemption?
6. **Founder age** (turns 18 on 2026-11-10) — can he lawfully contract as the App Store
   seller and data controller, and what minimum user age must the app enforce given health
   data collection (COPPA, UK Children's Code / Age Appropriate Design Code)?
7. **Guideline 5.1.1(ix)** says apps in highly regulated fields or requiring sensitive user
   information should be submitted by a legal entity rather than an individual developer —
   should a company be formed before submission, and in which jurisdiction, given US and UK
   distribution?
8. **Retention and deletion** — what retention periods and deletion timeframes must the
   privacy policy commit to, and must a deletion request propagate to the vision API
   vendor's request logs and any server-side photo cache?
9. **Storing health data in the user's own iCloud via CloudKit** — does that change the
   controller/processor analysis, the breach-notification exposure, or the data subject
   access request obligations compared with a developer-operated backend?
10. **Auto-renewing subscription consumer law** — what must the paywall, confirmation and
    receipts say to satisfy UK auto-renewal and cancellation rules and US state automatic
    renewal laws, beyond Apple's own 3.1.2(c) disclosure requirements?
11. **Trademark** — USPTO and UKIPO class 9 clearance for "ZeroLog" before the App Store
    listing exists (already flagged as outstanding in `references/decisions.md`).
