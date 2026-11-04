tau = 0.9. Unit = row (utterance). bare: 1 run per row. mem2/mem4: 3 seeded fact samples per row, shown as mean [min, max] over seeds.

#### route, cal180 (calibration split, diagnostic reuse: it fitted priors/tau, so not held out) (n = 15 rows)

| condition | argmax correct | handled at tau | correct of handled | confident errors | ECE | mean conf |
|---|---|---|---|---|---|---|
| bare | 12/15 | 7/15 | 7 | 0 | 0.127 | 0.820 |
| mem2 | 12 [12, 12]/15 | 5 [5, 5]/15 | 5 [5, 5] | 0 [0, 0] | 0.178 [0.140, 0.244] | 0.729 [0.712, 0.752] |
| mem4 | 11.7 [11, 12]/15 | 4.7 [4, 5]/15 | 4.7 [4, 5] | 0 [0, 0] | 0.135 [0.131, 0.138] | 0.715 [0.701, 0.725] |

#### route, authored (48 offline utterances written for this bench; labels are mine, not frozen or teacher-checked) (n = 48 rows)

| condition | argmax correct | handled at tau | correct of handled | confident errors | ECE | mean conf |
|---|---|---|---|---|---|---|
| bare | 36/48 | 21/48 | 21 | 0 | 0.108 | 0.760 |
| mem2 | 36.7 [36, 38]/48 | 12 [12, 12]/48 | 12 [12, 12] | 0 [0, 0] | 0.130 [0.091, 0.152] | 0.680 [0.674, 0.692] |
| mem4 | 36 [35, 37]/48 | 10.7 [10, 12]/48 | 10.7 [10, 12] | 0 [0, 0] | 0.111 [0.093, 0.127] | 0.656 [0.649, 0.662] |

#### route, all rows (n = 63 rows)

| condition | argmax correct | handled at tau | correct of handled | confident errors | ECE | mean conf |
|---|---|---|---|---|---|---|
| bare | 48/63 | 28/63 | 28 | 0 | 0.113 | 0.774 |
| mem2 | 48.7 [48, 50]/63 | 17 [17, 17]/63 | 17 [17, 17] | 0 [0, 0] | 0.116 [0.100, 0.135] | 0.692 [0.684, 0.699] |
| mem4 | 47.7 [46, 49]/63 | 15.3 [14, 17]/63 | 15.3 [14, 17] | 0 [0, 0] | 0.101 [0.078, 0.120] | 0.670 [0.667, 0.675] |

#### toolChoice, cal180 (calibration split, diagnostic reuse: it fitted priors/tau, so not held out) (n = 15 rows)

| condition | argmax correct | handled at tau | correct of handled | confident errors | ECE | mean conf |
|---|---|---|---|---|---|---|
| bare | 12/15 | 12/15 | 12 | 0 | 0.102 | 0.843 |
| mem2 | 12 [12, 12]/15 | 5.7 [5, 6]/15 | 5.7 [5, 6] | 0 [0, 0] | 0.186 [0.177, 0.202] | 0.774 [0.755, 0.791] |
| mem4 | 12 [12, 12]/15 | 5.7 [5, 7]/15 | 5.7 [5, 7] | 0 [0, 0] | 0.208 [0.195, 0.224] | 0.731 [0.720, 0.751] |

#### toolChoice, authored (48 offline utterances written for this bench; labels are mine, not frozen or teacher-checked) (n = 20 rows)

| condition | argmax correct | handled at tau | correct of handled | confident errors | ECE | mean conf |
|---|---|---|---|---|---|---|
| bare | 19/20 | 14/20 | 14 | 0 | 0.112 | 0.871 |
| mem2 | 17.3 [17, 18]/20 | 9.3 [9, 10]/20 | 9.3 [9, 10] | 0 [0, 0] | 0.166 [0.157, 0.174] | 0.825 [0.819, 0.831] |
| mem4 | 17 [17, 17]/20 | 7.7 [7, 8]/20 | 7.7 [7, 8] | 0 [0, 0] | 0.135 [0.112, 0.170] | 0.811 [0.809, 0.814] |

#### toolChoice, all rows (n = 35 rows)

| condition | argmax correct | handled at tau | correct of handled | confident errors | ECE | mean conf |
|---|---|---|---|---|---|---|
| bare | 31/35 | 26/35 | 26 | 0 | 0.108 | 0.859 |
| mem2 | 29.3 [29, 30]/35 | 15 [14, 16]/35 | 15 [14, 16] | 0 [0, 0] | 0.145 [0.139, 0.153] | 0.803 [0.798, 0.807] |
| mem4 | 29 [29, 29]/35 | 13.3 [12, 15]/35 | 13.3 [12, 15] | 0 [0, 0] | 0.145 [0.112, 0.174] | 0.777 [0.771, 0.785] |

#### Paired change vs bare (all rows; per-row seed mean; cluster bootstrap over rows, 4000 resamples, 95% CI; exact sign test over rows)

| decision | gold class | condition | metric | mean change per row | 95% CI | rows down / up / same | sign-test p |
|---|---|---|---|---|---|---|---|
| route | all (n=63) | mem2 | confidence | -0.082 | [-0.108, -0.056] | 56 / 7 / 0 | 1.4e-10 |
| route | all (n=63) | mem2 | handled at tau | -0.175 | [-0.270, -0.090] | 12 / 0 / 51 | 0.00049 |
| route | all (n=63) | mem2 | argmax correct | +0.011 | [-0.032, +0.058] | 3 / 3 / 57 | 1 |
| route | all (n=63) | mem4 | confidence | -0.104 | [-0.135, -0.074] | 57 / 6 / 0 | 1.6e-11 |
| route | all (n=63) | mem4 | handled at tau | -0.201 | [-0.296, -0.111] | 15 / 0 / 48 | 6.1e-05 |
| route | all (n=63) | mem4 | argmax correct | -0.005 | [-0.063, +0.053] | 5 / 4 / 54 | 1 |
| route | tool (n=24) | mem2 | confidence | -0.087 | [-0.107, -0.069] | 24 / 0 / 0 | 1.2e-07 |
| route | tool (n=24) | mem2 | handled at tau | -0.292 | [-0.472, -0.125] | 8 / 0 / 16 | 0.0078 |
| route | tool (n=24) | mem4 | confidence | -0.118 | [-0.145, -0.094] | 24 / 0 / 0 | 1.2e-07 |
| route | tool (n=24) | mem4 | handled at tau | -0.333 | [-0.528, -0.167] | 9 / 0 / 15 | 0.0039 |
| route | answer_local (n=13) | mem2 | confidence | -0.222 | [-0.272, -0.172] | 13 / 0 / 0 | 0.00024 |
| route | answer_local (n=13) | mem2 | handled at tau | -0.308 | [-0.538, -0.077] | 4 / 0 / 9 | 0.12 |
| route | answer_local (n=13) | mem4 | confidence | -0.275 | [-0.323, -0.227] | 13 / 0 / 0 | 0.00024 |
| route | answer_local (n=13) | mem4 | handled at tau | -0.308 | [-0.538, -0.077] | 4 / 0 / 9 | 0.12 |
| route | escalate_cloud (n=15) | mem2 | confidence | -0.024 | [-0.029, -0.019] | 15 / 0 / 0 | 6.1e-05 |
| route | escalate_cloud (n=15) | mem2 | handled at tau | +0.000 | [+0.000, +0.000] | 0 / 0 / 15 | 1 |
| route | escalate_cloud (n=15) | mem4 | confidence | -0.029 | [-0.036, -0.023] | 15 / 0 / 0 | 6.1e-05 |
| route | escalate_cloud (n=15) | mem4 | handled at tau | -0.044 | [-0.111, +0.000] | 2 / 0 / 13 | 0.5 |
| route | clarify (n=11) | mem2 | confidence | +0.014 | [-0.042, +0.063] | 4 / 7 / 0 | 0.55 |
| route | clarify (n=11) | mem2 | handled at tau | +0.000 | [+0.000, +0.000] | 0 / 0 / 11 | 1 |
| route | clarify (n=11) | mem4 | confidence | +0.027 | [-0.018, +0.075] | 5 / 6 / 0 | 1 |
| route | clarify (n=11) | mem4 | handled at tau | +0.000 | [+0.000, +0.000] | 0 / 0 / 11 | 1 |
| toolChoice | all (n=35) | mem2 | confidence | -0.056 | [-0.092, -0.018] | 28 / 7 / 0 | 0.00051 |
| toolChoice | all (n=35) | mem2 | handled at tau | -0.314 | [-0.476, -0.152] | 14 / 1 / 20 | 0.00098 |
| toolChoice | all (n=35) | mem2 | argmax correct | -0.048 | [-0.124, +0.000] | 2 / 0 / 33 | 0.5 |
| toolChoice | all (n=35) | mem4 | confidence | -0.082 | [-0.124, -0.037] | 32 / 3 / 0 | 4.2e-07 |
| toolChoice | all (n=35) | mem4 | handled at tau | -0.362 | [-0.533, -0.200] | 15 / 1 / 19 | 0.00052 |
| toolChoice | all (n=35) | mem4 | argmax correct | -0.057 | [-0.143, +0.000] | 2 / 0 / 33 | 0.5 |

#### What the route decision does with each request (offline, all rows)

Model acts: conf >= tau and argmax is the gold option. Falls back: conf < tau. The app then takes the escalate_cloud fallback (offline: the answerability decision, then chat or an offline notice) unless a deterministic rule intercepts first. Wrong and confident: conf >= tau with the wrong option. mem2/mem4 counts are rows, mean [min, max] over 3 seeds.

| gold route | rows | condition | model acts | falls back | wrong and confident |
|---|---|---|---|---|---|
| tool | 24 | bare | 9 | 15 | 0 |
| tool | 24 | mem2 | 2 [2, 2] | 22 [22, 22] | 0 [0, 0] |
| tool | 24 | mem4 | 1 [0, 2] | 23 [22, 24] | 0 [0, 0] |
| answer_local | 13 | bare | 4 | 9 | 0 |
| answer_local | 13 | mem2 | 0 [0, 0] | 13 [13, 13] | 0 [0, 0] |
| answer_local | 13 | mem4 | 0 [0, 0] | 13 [13, 13] | 0 [0, 0] |
| escalate_cloud | 15 | bare | 15 | 0 | 0 |
| escalate_cloud | 15 | mem2 | 15 [15, 15] | 0 [0, 0] | 0 [0, 0] |
| escalate_cloud | 15 | mem4 | 14.3 [14, 15] | 0.7 [0, 1] | 0 [0, 0] |
| clarify | 11 | bare | 0 | 11 | 0 |
| clarify | 11 | mem2 | 0 [0, 0] | 11 [11, 11] | 0 [0, 0] |
| clarify | 11 | mem4 | 0 [0, 0] | 11 [11, 11] | 0 [0, 0] |
