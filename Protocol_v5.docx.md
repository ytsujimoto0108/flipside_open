# Research Protocol: The Impact of Flipping Dichotomous Outcomes in Meta-Analysis

Yasushi Tsujimoto^1,2,3,4^, Yuki Kataoka^3,5,6,7^, Yusuke Tsutsumi^3,8,9^, Ryuhei So^2,3,10^, and Toshi A Furukawa^11^

1\. Oku Medical Clinic, Shinmori 7-1-4, Asahi-ku, Osaka 535-0022, Japan

2\. Department of Health Promotion and Human Behavior, Kyoto University Graduate School of Medicine / School of Public Health, Kyoto University, Yoshida Konoe-cho, Sakyo-ku, Kyoto 606-8501, Japan.

3\. Scientific Research WorkS Peer Support Group (SRWS-PSG), Osaka, Japan

4\. Division of Rheumatology, Department of Internal Medicine, Showa University School of Medicine, Shinagawa-ku, Tokyo, Japan

5\. Center for Postgraduate Clinical Training and Career Development, Nagoya University Hospital, 65, Tsurumai-cho, Showa-ku, Nagoya-city, Aichi, Japan

6\. Center for Medical Education, Graduate School of Medicine, Nagoya University, 65, Tsurumai-cho, Showa-ku, Nagoya-city, Aichi, Japan

7\. Department of Healthcare Epidemiology, Kyoto University Graduate School of Medicine / Public Health, Yoshida Konoe-cho, Sakyo-ku, Kyoto 606-8501, Japan

8\. Department of Emergency Medicine, National Hospital Organization Mito Medical Center, 280 Sakuranosato Ibarakimachi Higashiibarakigun, Ibaraki, 311-3117, Japan

9\. Department of Human Health Science, Kyoto University Graduate School of Medicine, Kyoto, Japan

10\. Department of Psychiatry, Okayama Psychiatric Medical Center, Shikatahonmachi 3-16, Kita-ku, Okayama, 700-0915 Japan

11\. Office of Institutional Advancement and Communications, Kyoto University, Kyoto, Japan

## 1\. Introduction and Rationale

In primary studies, dichotomous outcomes that are two sides of the same clinical coin—such as mortality and survival—convey equivalent information because the odds ratio (OR) or risk ratio (RR) for one can be readily derived from the other without changing the interpretation of the effect \[Deeks, Higgins, and Altman (2022)\]. Conversely, in a meta-analysis, the weight assigned to each study is a critical component of the pooled effect estimate. Flipping the outcome (for example, from mortality to survival) switches the event and non-event counts, altering within-study variances, continuity corrections when data are sparse, and consequently the contribution each study makes to the summary effect \[Sweeting, Sutton, and Lambert (2004); Bradburn et al. (2007)\]. In most cases, using odds ratios mathematically avoids this issue, but many systematic reviews use risk ratio as an effect measure. As a simple example, when neither arm records any events (a double-zero trial), researchers usually omit the study from the meta-analysis \[Sweeting, Sutton, and Lambert (2004)\]. If the outcome is flipped so that “no event” counts as the event, the same study retains its data but now enters the meta-analysis with positive weight and an implied risk ratio of 1\.

Empirical work examined some aspects of this question. A previous study explicitly flipped event definitions within Cochrane reviews and compared the p-values of the Cochran’s Q test. It found that the risk ratio of the harmful event appeared more consistent, whereas the selection of beneficial or harm outcomes for therapeutic reviews is less clear \[Deeks (2002)\]. However, these early explorations focused on heterogeneity metrics and did not evaluate how outcome switching affects the pooled estimates or the certainty of evidence.

This study therefore investigates whether flipping such dichotomous outcomes systematically affects the results of meta-analyses and, eventually, the Grading of Recommendations, Assessment, Development and Evaluation (GRADE) certainty of evidence judgment.

## 2\. Objectives

The objective is to quantify how pooled effect estimates, their precision, and GRADE certainty of evidence judgements change when mortality or survival outcomes are analysed in their original versus flipped formulation.

## 3\. Methods

### 3.1. Study Design

This will be a meta-epidemiological study based on a cohort of Cochrane systematic reviews.

### 3.2. Eligibility Criteria

#### *3.2.1. Inclusion Criteria*

We will include Cochrane systematic reviews from its inception to September 30, 2022 that meet the following criteria:

* **Type of studies:** The review includes only randomized controlled trials (RCTs).
* **Version of review:** We only include the most recent version of the reviews when one or more updates are available.
* **Type of analysis and outcome:** A pair-wise meta-analysis using a risk ratio (RR) or odds ratio (OR) is performed for a dichotomous outcome related to “death” or “survival”. Other complementary dichotomous outcome pairs, such as response and non-response, will not be included.

#### *3.2.2. Exclusion Criteria*

We will exclude reviews or meta-analyses if any of the following criteria are met:

* Meta-analyses where “death” is reported as only part of a composite outcome will be excluded.
* Meta-analyses where it is not possible to extract the 2x2 table for the relevant “death” or “survival” outcome from the meta-analysis.
* Reviews that the statistical data cannot be downloaded from the Cochrane library.

### 3.3. Data source

This study will utilize a dataset from a previous meta-epidemiological study by the author \[Tsujimoto et al. (2024)\]. The dataset was created by searching the Cochrane Database of Systematic Reviews for intervention reviews from its inception to September 30, 2022\. In the original study, relevant reviews were scraped, and data were downloaded from the Cochrane Library’s website using the Python Selenium package. The data were then loaded into R statistical software, and eligibility was checked according to the criteria outlined above. For this study, we will use the pre-existing, curated dataset.

### 3.4. Screening

First, we will identify relevant Cochrane reviews by filtering the outcome names in the statistical data. We will include reviews where a meta-analysis using an OR or RR has been performed on an outcome containing the terms “death,” “mortality,” “fatality,” “alive” or “survival.” The presence of these terms will be determined algorithmically using exact keyword matching. Outcome pairs outside the death/survival domain, including response/non-response outcomes, will not be screened or included. We will also examine the outcome name string to determine whether a matched death/survival keyword refers to the outcome itself or appears only as part of a composite outcome label, and we will exclude the latter (e.g., “mortality or morbidity” or “death or myocardial infarction”). In addition, we will examine the associated study data entries and exclude outcomes for which none contains all four cells required to reconstruct a 2×2 table (events and total participants in both arms). Eligible meta-analyses within these reviews will then be identified by retaining only dichotomous outcomes with data from at least two studies.

### 3.5. Data Extraction

For each eligible meta-analysis identified through the screening process, we will extract the following data through automated parsing of the rm5 files:

Bibliographic data of the Cochrane review. Outcome definition (survival or mortality) Number of participants and events for each study included in the meta-analysis (i.e., the 2x2 table data). The type of statistical model used for the meta-analysis

### 3.6. Data Analysis

We will tabulate the characteristics of meta-analyses in the included reviews (number of total participants, number of total events, control event rates, original effect measures (RR or OR), statistical significance, number of meta-analyses including at least one single-zero or double-zero study, and whether the outcome was originally reported as survival or mortality).

#### *3.6.1 Primary analysis*

For each included meta-analysis, we will first run two analyses using random-effects Mantel-Haenszel models:

Original analysis: use the 2x2 data according to the event definition encoded for that meta-analysis in the Cochrane review. Flipped analysis: recode the complementary event definition (new events \= total − original events).

To handle single-zero studies, a continuity correction adding 0.5 to all four cells in 2x2 tables will be applied. Double-zero studies will be omitted from the analyses. This model was chosen because it is one of the most commonly used methods for Cochrane reviews and is implemented in Cochrane’s Review Manager (RevMan) software (Deeks, Higgins, and Altman 2022; Tsujimoto et al. 2024).

We will then compare the statistical significance, precision and GRADE imprecision rating between original and flipped analyses. To evaluate changes in precision, we will compare the ratio of the upper to the lower limit of the 95% confidence interval for each pooled estimate in the original and flipped analyses. Following GRADE guidance on contextualised certainty ratings, we will transform pooled RR estimates and 95% CIs into absolute risk differences using the corresponding control event rate (Schünemann et al. 2022). For this GRADE-focused evaluation, we will compare (a) the original analysis and (b) the flipped-only analysis (i.e., using the flipped RR directly, without reciprocal re-expression). The control event rate for each meta-analysis will be estimated using a random-effects binomial-normal generalized linear mixed model with a logit link, fitted to the study-specific control-group event counts and denominators for the corresponding outcome definition. If this proportion meta-analysis fails to converge or cannot be estimated because of degenerate data, we will use the aggregate control event rate, calculated as the total number of events divided by the total number of participants in the control groups. We will benchmark these absolute effects against the GRADE thresholds of 13, 32, and 62 events per 1000 persons, which mark the transitions between trivial, small, moderate, and large effects (Wiercioch et al. 2025). For each orientation, we will count how many thresholds are crossed by the ARD 95% CI, then compare these counts and summarize their difference (flipped minus original).

For effect-estimate agreement plots, we will re-express the flipped pooled RR in the orientation of the original outcome by taking its reciprocal, so that values below or above 1 indicate effects in the same direction as in the original analysis. We denote RRo as the original pooled RR, RRflip as the flipped pooled RR before reciprocal re-expression, and RRf as the reciprocal of RRflip (RRf \= 1 / RRflip). We define the ratio of risk ratios as RRR \= RRf / RRo. We will use a Bland-Altman plot on the log scale, with the x-axis defined as the mean of log(RRo) and log(RRf), and the y-axis defined as their difference, log(RRf) \- log(RRo), which equals log(RRR) \[Bland and Altman (1999)\].

To quantify the difference in estimates between the two orientations, we will calculate the ratio of risk ratios (RRR), defined as RRf divided by RRo. A histogram will then be used to describe the distribution of the RRRs.

#### *3.6.2 Subgroup analysis*

We will conduct pre-specified subgroup analyses to explore potential heterogeneity of the impact of flipping outcomes based on the previous work (Efthimiou et al. 2019; Tsujimoto et al. 2024). In these subgroup analyses, the quantity to be compared between subgroup levels will be the ratio of risk ratios (RRR).

total sample size (\<1000 vs ≥1000 participants); baseline control event rate (\<5% vs ≥5%); presence vs absence of meta-analyses that include single-zero or double-zero studies.

For each subgroup level, we will summarize the distribution of RRR using the median and interquartile range (IQR), and visually compare subgroup levels using a forest-style plot (point \= median RRR, horizontal line \= IQR).

All analyses and visualisations will be conducted using Python or R.

## Funding

This work was supported by JSPS KAKENHI Grant Number 25K13447.

# Reference

Bland, J Martin, and Douglas G Altman. 1999\. “Measuring Agreement in Method Comparison Studies.” *Statistical Methods in Medical Research* 8 (2): 135–60.

Bradburn, Mark J., Jonathan J. Deeks, Jesse A. Berlin, and A. Russell Localio. 2007\. “Much Ado about Nothing? A Comparison of the Performance of Meta-Analytical Methods with Rare Events.” *Journal of Clinical Epidemiology* 60 (1): 1–9. [https://doi.org/10.1016/j.jclinepi.2006.09.003](https://doi.org/10.1016/j.jclinepi.2006.09.003).

Deeks, Jonathan J. 2002\. “Issues in the Selection of a Summary Statistic for Meta-Analysis of Clinical Trials with Binary Outcomes.” *Statistics in Medicine* 21 (11): 1575–1600. [https://doi.org/10.1002/sim.1188](https://doi.org/10.1002/sim.1188).

Deeks, Jonathan J., Julian P. T. Higgins, and Douglas G. Altman. 2022\. “Chapter 10: Analysing Data and Undertaking Meta-Analyses.” In *Cochrane Handbook for Systematic Reviews of Interventions*, edited by Julian P. T. Higgins, James Thomas, Jacqueline Chandler, Miranda Cumpston, Tianjing Li, Matthew J. Page, and Vivian A. Welch, Version 6.3. Cochrane. [https://training.cochrane.org/handbook/current/chapter-10](https://training.cochrane.org/handbook/current/chapter-10).

Efthimiou, Orestis, Gerta Rücker, Guido Schwarzer, Julian P. T. Higgins, Matthias Egger, and Georgia Salanti. 2019\. “Network Meta-Analysis of Rare Events Using the Mantel-Haenszel Method.” *Statistics in Medicine* 38 (16): 2992–3012. [https://doi.org/10.1002/sim.8158](https://doi.org/10.1002/sim.8158).

Schünemann, Holger J., Ignacio Neumann, Monica Hultcrantz, Romina Brignardello-Petersen, Linan Zeng, M. Hassan Murad, Ariel Izcovich, et al. 2022\. “GRADE Guidance 35: Update on Rating Imprecision for Assessing Contextualized Certainty of Evidence and Making Decisions.” *Journal of Clinical Epidemiology* 150: 225–42. [https://doi.org/10.1016/j.jclinepi.2022.07.015](https://doi.org/10.1016/j.jclinepi.2022.07.015).

Sweeting, Michael J., Alexander J. Sutton, and Paul C. Lambert. 2004\. “What to Add to Nothing? Use and Avoidance of Continuity Corrections in Meta-Analysis of Sparse Data.” *Statistics in Medicine* 23 (9): 1351–75. [https://doi.org/10.1002/sim.1761](https://doi.org/10.1002/sim.1761).

Tsujimoto, Yasushi, Yusuke Tsutsumi, Yuki Kataoka, Akihiro Shiroshita, Orestis Efthimiou, and Toshi A. Furukawa. 2024\. “The Impact of Continuity Correction Methods in Cochrane Reviews with Single-Zero Trials with Rare Events: A Meta-Epidemiological Study.” *Research Synthesis Methods* 15 (5): 769–79. [https://doi.org/10.1002/jrsm.1720](https://doi.org/10.1002/jrsm.1720).

Wiercioch, Wojtek, Gian Paolo Morgano, Thomas Piggott, Robby Nieuwlaat, Ignacio Neumann, Bernardo Sousa-Pinto, Pablo Alonso-Coello, et al. 2025\. “GRADE Guidance: Using Thresholds for Judgments on Health Benefits and Harms in Decision Making (GRADE Guidance 42).” *Annals of Internal Medicine*. [https://doi.org/10.7326/ANNALS-24-02013](https://doi.org/10.7326/ANNALS-24-02013).
