# Comparison anti-patterns

The patterns that look like comparisons but degrade trust. Easy to ship; cost shows up in conversion, brand reputation, and audience trust.

______________________________________________________________________

## The feature-list-dump comparison

The pattern. Every feature × every option. No decision support.

The signal. Users skim; do not choose; tool produces no conversion lift.

The cure. Cut to 8-12 decision-relevant axes. Add recommendation.

______________________________________________________________________

## The hidden-recommendation comparison

The pattern. Defaults bias toward brand without disclosure.

The signal. Sophisticated audiences notice; trust collapses.

The cost. Long-term brand damage.

The cure. Honest defaults; explicit recommendation; acknowledge competitor strengths.

______________________________________________________________________

## The all-checkmarks comparison

The pattern. Every option has every feature; checkmarks across the rows.

The signal. Rows produce no signal; users skim.

The cure. Cut generic-checkmark rows. Replace with specifics that differentiate.

______________________________________________________________________

## The terminology-confused comparison

The pattern. Each vendor's terminology used in their column; user cannot tell if features match.

The signal. Users confused; comparison breaks semantically.

The cure. Normalize terminology. Vendor names in subtext; functional descriptions in main label.

______________________________________________________________________

## The hidden-cost comparison

The pattern. Headline pricing visible; overage, fees, integrations not surfaced.

The signal. Users compare on visible price; learn about hidden costs later; feel deceived.

The cure. Total cost of ownership surfaced.

______________________________________________________________________

## The apples-to-oranges comparison

The pattern. Options compared that are genuinely different things.

The signal. Comparison feels strained; axes do not apply cleanly.

The cure. Compare options the audience actually considers together. Separate tools for separate categories if needed.

______________________________________________________________________

## The no-recommendation comparison

The pattern. Tool lists; user decides alone.

The signal. High abandonment; conversion lift absent.

The cure. Add recommendation with reasoning.

______________________________________________________________________

## The contradicts-itself comparison

The pattern. Comparison shows competitor winning on most axes; tool recommends brand anyway.

The signal. Users notice the contradiction; trust collapses.

The cure. Recommendation aligns with comparison; or recommendation defends the contradiction explicitly.

______________________________________________________________________

## The stale comparison

The pattern. Information from 6+ months ago.

The signal. Users notice; trust drops.

The cure. Quarterly maintenance.

______________________________________________________________________

## The over-filtered comparison

The pattern. 12+ filters; user paralysis at filter step.

The signal. High drop-off before the comparison loads.

The cure. Reduce filter count; default-heavy.

______________________________________________________________________

## The under-filtered comparison

The pattern. Tool too rigid; one fixed view.

The signal. Specific segments convert poorly.

The cure. Add filters where audiences split.

______________________________________________________________________

## The mobile-broken comparison

The pattern. Grid designed for desktop; mobile cramped or scroll-required.

The signal. Mobile conversion much lower.

The cure. Mobile-first design.

______________________________________________________________________

## The methodology-hidden comparison

The pattern. Tool shown without explaining how comparison was built.

The signal. Sophisticated users question the tool.

The cure. Methodology disclosure.

______________________________________________________________________

## The audience-stereotype comparison

The pattern. Audience-segment recommendations rely on stereotypes ("enterprise = big and slow").

The signal. Users in those segments feel mis-served.

The cure. Audience-segment recommendations based on real needs, not assumptions.

______________________________________________________________________

## The over-recommend comparison

The pattern. Tool recommends in cases where genuine differentiator does not exist.

The signal. Users notice the recommendation feels arbitrary.

The cure. "We cannot rank these for you" is sometimes the honest answer.

______________________________________________________________________

## The competitor-omission comparison

The pattern. Important competitor missing from the comparison.

The signal. Users ask "where is X?" or feel comparison is incomplete.

The cure. Include relevant competitors. If a competitor is omitted intentionally, disclose why.

______________________________________________________________________

## The bias-flattering-axis-selection comparison

The pattern. Axes chosen where brand wins; axes hidden where brand loses.

The signal. Sophisticated audiences notice axis selection.

The cure. Honest axis selection. Detail in `references/axis-selection-patterns.md`.

______________________________________________________________________

## The marketing-checkbox comparison

The pattern. Every option's marketing checkboxes laid out as comparison.

The signal. Comparison reads like marketing brochures rather than analysis.

The cure. Replace marketing checkboxes with specific functional capabilities.

______________________________________________________________________

## How to detect anti-patterns

Audit cadence. Quarterly review.

**Audit questions per tool.**

- Is the tool feature-list-dump (anti-pattern check)?
- Does the recommendation acknowledge competitor strengths (anti-pattern check: hidden-recommendation)?
- Are rows differentiating (anti-pattern check: all-checkmarks)?
- Is terminology normalized (anti-pattern check: terminology-confused)?
- Are total costs surfaced (anti-pattern check: hidden-cost)?
- Are options apples-to-apples (anti-pattern check: apples-to-oranges)?
- Is recommendation present (anti-pattern check: no-recommendation)?
- Does recommendation align with comparison (anti-pattern check: contradicts-itself)?
- Is information current (anti-pattern check: stale)?
- Are filters calibrated (anti-pattern check: over-filtered, under-filtered)?
- Does mobile work (anti-pattern check: mobile-broken)?
- Is methodology disclosed (anti-pattern check: methodology-hidden)?

**The retire decision.** Tools failing multiple checks warrant redesign or retirement.

______________________________________________________________________

## Methodology-level choices that stay in the public skill

The catalog of anti-patterns. Signal-pattern-cost framing. Cures matched. Audit cadence and questions. The retire decision.

## Implementation choices that stay internal

Specific anti-patterns the team has shipped and lessons learned. Specific portfolio audit results. The team's audit calendar. These vary by team.
