# E-Commerce Customer Analytics — Findings Log

## RFM Customer Segmentation (sql/02_rfm_segmentation.sql)

### Key finding: Olist is a single-purchase business
- 97% of unique customers (90,557 of 93,358) place exactly one order
- 2.76% place a second order; only 0.24% reach 3+ orders
- This shapes every other analytical question that follows

### Methodology note
- Standard RFM segmentation produced misleading results because Frequency has virtually no variation across customers (97% have F=1)
- Resulting "Champions" segment averaged 1.0 orders/customer — meaning every "Champion" was a one-time buyer
- Redesigned as two-tier segmentation:
  - **Tier 1 (one-time buyers):** segmented by Recency × Monetary alone
  - **Tier 2 (repeat buyers):** full RFM with frequency-based tiers

### Key segments (revised model)
| Segment | Customers | % | Revenue | % | Avg Value | Avg Orders |
|---|---|---|---|---|---|---|
| Lost / Hibernating | 21,821 | 23% | $5.15M | 33% | $236 | 1.0 |
| New Customer | 20,982 | 22% | $5.02M | 33% | $239 | 1.0 |
| One-Time Mid-Tier | 18,068 | 19% | $2.74M | 18% | $152 | 1.0 |
| New High-Value | 15,365 | 16% | $856K | 6% | $56 | 1.0 |
| Lost High-Value | 14,321 | 15% | $782K | 5% | $55 | 1.0 |
| Active Repeat (2) | 1,492 | 1.6% | $428K | 2.8% | $287 | 2.0 |
| Lapsed Repeat (2) | 1,081 | 1.2% | $321K | 2.1% | $297 | 2.0 |
| Loyal Repeat (3) | 181 | 0.2% | $78K | 0.5% | $433 | 3.0 |
| VIP Repeat (4+) | 47 | 0.05% | $37K | 0.2% | $788 | 4.9 |

### Strategic implications
1. **Repeat customers are 3-15× more valuable per person, but only 5.6% of total revenue.** The opportunity space is huge.
2. **"Lost High-Value" (14,321 customers, $782K revenue, 138 days dormant) is the highest-leverage win-back segment.** They've already validated they'll buy; easier to re-engage than acquire new.
3. **The central business question becomes: why don't first-time buyers come back?** This is what we investigate in the satisfaction / operations section next.

## Cohort Retention Analysis — Detailed Findings

### Retention is structurally near-zero
- Month-1 retention across mature cohorts ranges from 0.18% to 0.72%, with most cohorts between 0.4% and 0.6%
- Month-2 retention typically falls in the 0.2% to 0.4% range
- By month 4-5, retention is effectively zero across all cohorts
- For context: a typical 6,000-customer cohort retains roughly 30 customers into month 2 and fewer than 10 by month 5

### Acquisition was growing rapidly during this period
- New customer acquisition grew ~10x between January 2017 (717 customers) and November 2017 (7,060 customers)
- Cohort sizes stabilized in the 5,000-7,000 range through 2018
- Revenue growth during this period was driven almost entirely by new customer volume, not repeat purchases

### Notable pattern: occasional late returns
- Some 2017 cohorts show higher retention at month 6 than at month 5
- This suggests Olist's small repeat-buyer population tends to space purchases over longer intervals rather than buying monthly
- Implication: retention should be measured at quarterly or 6-month intervals rather than monthly to detect meaningful behavior

### Data caveat
- 2018 cohorts show truncated data because the dataset ends October 2018
- August 2018 cohort, for example, cannot have month-3 data
- This is a dataset limitation, not a retention failure

### Strategic implication
Olist operates as a structurally single-purchase marketplace. Retention investments (loyalty programs, email re-engagement, customer success outreach) are unlikely to generate meaningful ROI given retention is below 1% across all observed cohorts with no positive trend over time. Higher-leverage opportunities exist upstream of retention: optimizing acquisition cost, increasing average order value at first purchase, and improving the first-purchase experience to drive word-of-mouth referrals rather than direct repeat purchase.

## Satisfaction and Operations Analysis (sql/04_satisfaction_operations.sql)

### Review distribution
The platform generates 78.9 percent positive reviews (four or five stars), with the negative-review burden concentrated in the 9.8 percent one-star segment. The strategic question is therefore narrow: what causes a one-star review, and which interventions could prevent it.

### Finding 1: Delivery speed and estimate accuracy interact rather than acting independently
Cross-tabulating delivery speed against estimate accuracy reveals that the two variables produce a multiplicative effect on review scores rather than additive. Within the under-7-days delivery band, average review scores stay between 4.36 and 4.53 regardless of estimate accuracy. Within the 21-29-days band, orders delivered ahead of estimate maintain 3.92 to 3.98 average reviews while orders delivered late by four or more days collapse to 2.15 with a 66 percent negative-review rate. Within the 30+ days band, late-by-4-plus orders generate a 76.8 percent negative-review rate.

The customer experience is governed by the combination of these variables. When delivery is fast in absolute terms, the promise matters little. When delivery is slow, missing the promise on top of the slow delivery produces the catastrophic reviews.

### Finding 2: Olist's estimate window is normally conservative, but the cushion is eroded for the worst orders
Five-star orders are delivered 12.7 days ahead of estimate on average; one-star orders are delivered only 3.4 days ahead. Olist systematically pads its delivery estimates by approximately two weeks. The orders that generate one-star reviews are those where most of that cushion has been consumed by underlying delivery problems.

### Finding 3: Seller quality dispersion is highly skewed but contains a tractable problem
Among sellers with at least ten orders, 78 sellers (6.3 percent of the active seller base) fall in the Poor or Very Poor quality tiers. These sellers account for 4.3 percent of orders and 5.7 percent of revenue. Individual underperformers in the top-25 worst-seller list have negative-review rates between 28 and 64 percent, with one seller generating over 280 reviews at a 29 percent negative rate. The worst sellers are geographically concentrated in São Paulo state.

### Finding 4: Negative reviews concentrate in heavy and fragile product categories
Office furniture, fixed telephony, audio equipment, home comfort items, and bed/bath/table products generate negative-review rates of 18 to 25 percent, well above the platform average. The shared characteristic is that these categories involve larger, heavier, or more fragile items where delivery damage and dimensional mismatches are more likely.

### Strategic implications
Three intervention levers emerge from the analysis, ranked by operational tractability. The most tractable lever is seller-quality intervention: 78 underperforming sellers can be identified, audited, and either rehabilitated or removed, which would eliminate roughly five percent of negative reviews with minimal disruption. The second lever is estimate accuracy, which can be addressed by deliberately widening estimate windows for orders shipped to distant states or heavy categories where delays are more likely; the data demonstrates that customers tolerate wide promised windows better than missed promises. The third lever is raw delivery speed, which is the hardest to address because it involves underlying logistics infrastructure that the marketplace operator controls only indirectly.

Connecting back to the cohort retention finding: poor first-purchase experience is plausibly a major contributor to the near-zero retention rates observed across cohorts. A customer whose first Olist purchase arrived 30 days late and damaged is unlikely to return. The analyses converge on the same conclusion: investment in first-purchase experience offers higher leverage than direct retention investment.