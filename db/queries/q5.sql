SELECT
    r.run_id,
    r.folder || '/' || o.path AS file,
    o.sha256
FROM runs AS r
JOIN outputs AS o
    ON o.run_id = r.run_id
WHERE o.path = 'cohort.filtered.vcf.gz';
