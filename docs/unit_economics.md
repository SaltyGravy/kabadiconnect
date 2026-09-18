# KabadiConnect — Unit Economics Assessment

> **Status of these numbers**: illustrative, built from publicly reported ranges for
> India's informal e-waste sector (waste-picker daily earnings surveys, EPR/CPCB
> price-band reporting, multi-tier scrap-trade margin studies) and the platform's
> own pricing assumptions — **not yet validated against the two field-research
> collector interviews** (see `docs/dataset_documentation.md` for that gap). Treat
> this as the model to plug real numbers into, not a finished estimate.

## 1. How an informal collector earns today

A typical waste-picker/informal e-waste collector in an Indian city works through
a multi-tier informal chain:

```
Collector  →  Local aggregator/scrap shop  →  Bigger trader  →  (sometimes) processor
  (you)          takes a cut                    takes a cut         takes a cut
```

Because the collector has no visibility into the price the *aggregator* gets, no
way to verify weight/purity claims, and no leverage to shop around (relationship-
based, often credit-tied to one aggregator), reported literature and NGO field
studies on India's informal recycling sector consistently describe collectors
capturing **roughly 20–40% of the value the material eventually clears at the
first formal-adjacent buyer**, with cash-only, no-receipt transactions.

Illustrative monthly baseline (e-waste-focused collector, mid-sized city):

| Item | Illustrative value |
|---|---|
| Materials moved / month | ~150–300 kg mixed e-waste |
| Effective realized price | 60–75% of prevailing informal buying price (see reasons below) |
| Estimated monthly earnings | **₹6,000 – ₹13,000** |

Why realized price lags the "prevailing" price even in the informal channel:
- **Backyard processing losses**: burning cable insulation to get at copper
  destroys a portion of recoverable copper and destroys the wire's resale-whole
  value entirely; acid-leaching PCBs for gold recovers only some of the metal
  value and forecloses recovery of everything else (palladium, tin, tantalum) —
  the *brief's* stated problem, restated as a P&L line.
- **Information asymmetry**: no way to check today's rate or a specific
  recycler's offer before selling, so aggregators can (and, per field reports,
  routinely do) quote below prevailing rate.
- **No traceability / no leverage**: a dispute over quoted vs. paid weight has no
  record to point to.

## 2. What changes on KabadiConnect

| Mechanism in the app | Effect on collector earnings |
|---|---|
| Price Board (live, per-category, per-location, with trend) | Removes the single biggest source of underpayment: not knowing the going rate before a deal. |
| Direct match to *authorized* recyclers, ranked by offered rate | Cuts out one or more middle layers; recycler's `offered_rates` in the seed dataset run **~2–15% above the informal buying price** for the same material (recyclers can afford this because EPR-obligated producers pay *them* for documented, compliant volume). |
| Digital, GPS+timestamp+photo handover record with a unique reference | Gives the collector something to point to if a recycler under-pays vs. the quote — the anomaly-detection check (`AnomalyDetectionService`) flags exactly this pattern for the recycler side too. |
| Selling PCBs/cables/batteries *whole* instead of burning/leaching | Recovers material value the collector was otherwise destroying to self-extract copper/gold inefficiently and dangerously. |
| Earnings ledger | Turns informal, undocumented cash-in-hand into a legible history — a precondition for any future credit/microfinance access, even though this build doesn't implement that. |

Illustrative monthly earnings on-platform, same 150–300 kg/month collector:

| Item | Illustrative value |
|---|---|
| Effective realized price | 95–110% of prevailing *recycler-offered* price (vs. 60–75% of the lower informal price today) |
| Estimated monthly earnings | **₹9,500 – ₹19,000** |
| **Uplift vs. informal channel** | **~45–55%**, driven roughly half by better price capture and half by cutting a middle-layer |

This uplift is deliberately conservative: it assumes the same volume and mix of
materials, no pickup-service time savings, and no reduction in the collector's
own transport costs — all of which the matching/pickup-availability feature
could plausibly improve further once tested with real routes.

## 3. How the platform sustains itself

The collector side must stay **free and frictionless** — the brief is explicit
that this cannot become a compliance burden, and collectors are the most
price-sensitive, least able to absorb a fee. Revenue instead comes from the side
that gains a business benefit from formal, documented volume: recyclers and,
indirectly, the EPR-obligated producers who need proof of compliant sourcing.

| Revenue stream | Mechanism | Why the payer accepts it |
|---|---|---|
| **Transaction commission** (2–4% of `final_price`, charged to the recycler, not the collector) | Deducted at the "Mark as Paid" step | Recycler is paying for lead generation into their funnel plus a documented, EPR-defensible chain-of-custody record for material they'd otherwise have to source informally with no paper trail |
| **Recycler facility subscription** (flat monthly fee for priority ranking in `RecyclerMatchingService`, richer profile, pickup-route tools) | Optional tier | Authorized recyclers already pay for lead-gen/logistics elsewhere; this is cheaper and comes with compliance documentation attached |
| **Compliance/traceability reporting** (aggregated, anonymized volume + traceability exports sold to Producer Responsibility Organizations / EPR-obligated producers) | B2B data product built on the Traceability Dataset | PROs currently struggle to *prove* genuine formal-channel sourcing volumes; this dataset is exactly that proof, at a fraction of the cost of building their own field network |
| *(Not a revenue stream)* Digital payment processing | Optional, cash remains default per the brief | Kept optional so it's never a barrier to entry |

Illustrative break-even sketch for a single-city pilot (order-of-magnitude only):

- 12 recyclers (seed dataset size) × ₹2,000/month subscription ≈ ₹24,000/month
- Transaction commission at 3% on, say, 800 kg/month of matched material across
  all recyclers at an average ₹250/kg ≈ ₹6,000/month
- **Illustrative monthly platform revenue at pilot scale: ~₹30,000**, against
  hosting (Firebase free/Spark-to-Blaze tier at this volume is near-zero) and a
  small community-outreach cost — i.e. the model is designed to reach break-even
  at a *single-city, low-tens-of-recyclers* scale, not require national scale
  first.

The real numbers must come from the two field-research collector interviews and
conversations with 2–3 recyclers about what commission/subscription they'd
actually accept — this section is the model to fill in, not a final projection.
