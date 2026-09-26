# Troubleshooting Log

## Truncated-gzip acceptance test failed despite a working `gzip -t` check

**Symptom:** The `CUTGZIP` / truncated-gzip acceptance tests failed even though
`stage_validate` runs `gzip -t` on R1/R2 files and correctly rejects gzip files
that I truncate manually.

**Evidence:** I reproduced the harness fixture using its `fq()` function: 20
small repetitive FASTQ records piped to `gzip -c`. On my system,
`whole.fastq.gz` was only 109 bytes. The harness creates the corrupted fixture
with `head -c 120 whole.fastq.gz > cut_R1.fastq.gz`. Because 120 exceeds the
109-byte input size, the output was not truncated. Both files were 109 bytes,
and `gzip -t` returned 0 for both.

**Cause:** The fixture assumes the compressed 20-record FASTQ is larger than
120 bytes. On my system the repetitive synthetic reads compress below that
size, so `head -c 120` copies the complete gzip stream rather than removing its
tail.

**Resolution / verification:** I left the pipeline and supplied acceptance test
unchanged. To verify the validator independently, I truncated my 273 KB
development FASTQ to 120 bytes. `gzip -t` returned 1, and `stage_validate`
reported the affected sample and exited 65. This confirmed that the pipeline
correctly rejects a genuinely truncated gzip stream.

After the corrected acceptance harness was released, I downloaded the updated
test suite and confirmed that the same validator passed the truncated-gzip test
without any change to the pipeline logic.

## Week 2 deliberate failure: out-of-range array task

**Failure introduced:** I submitted array task 9 against the eight-sample
samplesheet.

**Evidence:** Explorer job `10620310_9` finished in 00:00:13 with state
`FAILED` and exit code `64:0`. Its stderr contained:

`task 9: no such row`

**Diagnosis / result:** The array-row guard correctly detected that task 9 had
no corresponding samplesheet row and refused to run. This prevents an
out-of-range array task from silently processing zero samples and exiting
successfully.

## Week 2 deliberate failure: job timeout

**Failure introduced:** I submitted NA12878 with a Slurm time limit of one
minute, much shorter than its measured runtime.

**Evidence:** Explorer job `10620350_1` had a time limit of `00:01:00` and was
recorded by `sacct` as `TIMEOUT` after `00:01:23`. The Slurm log reported that
job 10620350 on c3015 was cancelled due to the time limit.

**Diagnosis / result:** FastQC and fastp completed before the timeout, and BWA-MEM
had started alignment when Slurm terminated the job. The completed QC and
trimmed-read outputs remained, but no final NA12878 alignment BAM was published.
This is consistent with the pipeline writing the alignment to a temporary BAM
and publishing the final BAM only after successful completion and validation.

## Week 2 deliberate failure: failed array task blocks the cohort job

**Failure introduced:** I submitted out-of-range array task 9 as job
`10628934`, then submitted cohort job `10628935` with an
`afterok:10628934` dependency and `--kill-on-invalid-dep=yes`.

**Evidence:** Array task `10628934_9` finished as `FAILED` in 00:00:10 with
exit code `64:0`, and stderr reported `task 9: no such row`. The dependent
cohort job `10628935` was recorded as `CANCELLED` with elapsed time
`00:00:00`, and no cohort log files were created.

**Diagnosis / result:** The failed array task made the `afterok` dependency
unsatisfiable. Slurm therefore cancelled the dependent cohort job before it
started. This prevents cohort-level analysis from running when any required
per-sample task fails.

## Week 2 deliberate failure: cancellation during alignment and recovery

**Failure introduced:** I submitted NA12878 as Explorer job `10628964_1` and
manually cancelled it with `scancel` while BWA-MEM was actively processing
reads.

**Evidence:** Job `10628964_1` was recorded as `CANCELLED` after 00:01:15.
The BWA log showed reads being processed immediately before cancellation.
After cancellation, no final `NA12878.bam` had been published.

**Recovery / verification:** Without manually deleting the completed pipeline
outputs, I resubmitted the same sample as job `10628991_1`. FastQC and fastp
recognized their completed outputs and skipped them, while BWA-MEM,
MarkDuplicates, and HaplotypeCaller ran again. The recovery job completed in
00:08:30 with exit code `0:0`. The final alignment BAM and duplicate-marked BAM
both passed `samtools quickcheck`, the GVCF was readable by `bcftools`, and its
sample name was `NA12878`.

**Diagnosis / result:** The cancelled alignment was not mistaken for a completed
result. Completed upstream work was reused, while the interrupted stage and its
downstream stages were recomputed successfully.
