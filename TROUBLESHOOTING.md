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
