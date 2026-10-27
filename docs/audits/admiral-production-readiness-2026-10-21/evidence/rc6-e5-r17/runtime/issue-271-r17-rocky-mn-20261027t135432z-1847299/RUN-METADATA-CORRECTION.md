# Run-directory metadata correction

This run exercised Rocky R17 Single-Node despite `rocky-mn` in the directory
basename and captured run tag. The legacy suffix was inherited when the
Multi-Node harness was adapted. The executed harness, its SSH connections,
`admin-baseline.txt`, and the instance node-ID assertions all identify the same
Single-Node guest (`rc6e5r17-rocky-single`). The run log explicitly records
`topology=rocky-single-node`. No product code or runtime package was changed.

The source harness was corrected after this run to emit `rocky-sn` for future
Single-Node evidence. The archived `issue-271-single.sh` remains unchanged so
it represents the actual script used for this run.
