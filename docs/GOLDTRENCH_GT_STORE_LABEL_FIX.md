# Gold trench `.gt_store` label fix

ACME failed after the long-branch fix because the blank-cell path still jumped to `.gt_store`, but the label had been removed while introducing `.gt_store_gold` and `.gt_rows_done`.

Fixed by restoring a real `.gt_store:` path:

- writes the blank character to screen RAM
- writes black to color RAM to remove stale gold trails
- continues the same column loop safely
- jumps to `.gt_row_next` when the row is done

`static_audit.py` now includes a local dot-label guard so undefined local labels such as `.gt_store` are caught before ACME.
