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

## Week 3 deliberate failure: unpinned rebuild

**Failure introduced:** I deliberately built an image from an unpinned recipe:

`FROM ubuntu`

`RUN apt-get update && apt-get install -y curl`

The first build was performed on September 27. I saved its installed-package
list with `dpkg -l`. More than 24 hours later, I rebuilt the same recipe with:

`docker build --pull --no-cache --platform linux/amd64 -t w3-unpinned:day2 .`

I again saved the complete `dpkg -l` output and compared the two package lists
with `diff -u`.

**Evidence:** Both package lists contained 122 lines, and the comparison
returned `diff exit=0`, so there were no package differences between these two
particular builds. The second build nevertheless re-ran the unpinned
`apt-get update && apt-get install -y curl` step because `--no-cache` was used,
and `--pull` checked the current `ubuntu:latest` base. Both builds resolved the
base to
`ubuntu:latest@sha256:da6fc2be547864451aa253836dd926da33623312df4a9a243e35dc877c378a78`.

**Diagnosis / result:** The absence of a difference in this 24-hour interval
does not make the recipe reproducible. `ubuntu` is a mutable tag and `curl`
has no pinned package version, so a future rebuild can resolve to a different
base image or package version without any Dockerfile change. The production
image therefore pins its base-image tag and all required software versions.

## Week 3 deliberate failure: missing Apptainer bind

**Failure introduced:** On Explorer I verified that
`/scratch/han.meng1/BINF6610-assignment3/results/cohort.filtered.vcf.gz`
existed on the host, then deliberately ran the container without binding the
scratch path:

`apptainer exec --cleanenv "$SIF" bcftools view -h "$BROKEN_TARGET"`

**Evidence:** The command failed with:

`Failed to open file "/scratch/han.meng1/BINF6610-assignment3/results/cohort.filtered.vcf.gz" : No such file or directory`

and returned `missing-bind exit=255`.

I repeated the command with:

`--bind /scratch/han.meng1`

and it returned `with-bind exit=0`.

**Diagnosis / result:** A path that exists on the Explorer host is not
necessarily visible inside the container. The production Slurm jobs therefore
explicitly bind the required `/courses/BINF6610.202710` and scratch paths.

## Week 3 deliberate failure: incorrect GATK thread count

**Failure introduced:** I allocated four CPUs with Slurm but deliberately ran
a small HaplotypeCaller test with one PairHMM thread using
`--native-pair-hmm-threads 1`.

**Evidence:** GATK reported:

`Available threads: 4`

`Requested threads: 1`

I then repeated the test with the correct four-thread setting. GATK reported:

`Available threads: 4`

`Requested threads: 4`

**Diagnosis / result:** Allocating CPUs with Slurm does not by itself make an
application use them. The thread count must reach the container and the
application. The production jobs therefore pass `THREADS` and
`SLURM_CPUS_PER_TASK` explicitly through `apptainer exec --env`, and the
pipeline uses the requested thread count for HaplotypeCaller.

## Week 3 deliberate failure: wrong container architecture

**Failure introduced:** I deliberately built and pushed an ARM64 image, pulled
it into an Apptainer SIF on an Explorer compute node, and attempted to execute
it. The compute node reported `uname -m` as `x86_64`.

**Evidence:** Apptainer refused to execute the ARM64 SIF with:

`FATAL: While checking container encryption: could not open image /scratch/han.meng1/w3-arch-breakage/wrong-arm64.sif: the image's architecture (arm64) could not run on the host's (amd64)`

The command returned `wrong-arch exit=255`.

**Diagnosis / result:** An image can be built and transferred successfully yet
still be unusable on the target cluster if its CPU architecture is wrong. The
production image was therefore built explicitly with
`--platform linux/amd64` for Explorer's x86_64/amd64 compute nodes.
