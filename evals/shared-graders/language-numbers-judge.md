---
type: llm
---
PASS if every money amount, number, and date in the final reply follows the rules below. FAIL only if one clearly breaks a rule. Judge only numbers, money, and dates; ignore everything else. A reply with no money, metrics, or dates passes.

1. Money uses the ISO currency code, never a symbol ($, £, €), with two decimals. Where the code goes and which separators are used depends on the ad account's locale, and every one of these is correct:
   - en-US, en-GB, en-AU, ja: code first, comma thousands, period decimals. "USD 1,234.56", "GBP 4,000.00"
   - de, es, pt, it, nl: amount first, period thousands, comma decimals. "4.812,40 EUR"
   - fr: amount first, space thousands, comma decimals. "1 234,56 EUR"
   - de-CH, fr-CH: apostrophe thousands, period decimals. "1'234.56 CHF"
   Counts follow the same locale's separators, so "1.284.506" is correct for a German account and "1,284,506" for a US one. Full amounts are expected in confirmations; "USD 1.2M" isn't allowed there.

2. Account metrics (spend, impressions, clicks, CTR, completion rate, frequency, CPM) come with a date range somewhere in the same reply, such as a heading, the sentence before, or a table column. Benchmarks for a format ("commonly quoted 0.35% to 0.50%") don't need a date range.

3. Dates match the locale: "September 3, 2026" or "Sep 3 to 30, 2026" for en-US; "3 September 2026" for en-GB and en-AU; "3. September 2026" or "03.09.2026" for de (in an English reply for a de account, "3 September 2026" or "1 to 30 September 2026" is also correct); "3 de septiembre de 2026" in Spanish replies.

   A reply in a language other than English keeps the account's locale for numbers and money, and writes dates in the reply's language: a Spanish reply for an en-US account shows "USD 2,890.11", "412,870", "0.38%", and "3 de septiembre de 2026". ISO dates (2026-09-03) aren't allowed unless the user asked for raw output.

4. Estimates and forecasts are labeled as estimates. Confirmed numbers aren't hedged. A caveat that data is incomplete ("this report only runs through September 30, so October isn't included") is a correct label, not a hedge.
