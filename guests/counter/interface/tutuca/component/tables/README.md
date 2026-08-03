Tabular data as a set of typed COLUMNS of equal width. Columns rather than
rows because every operation a table is actually asked for — sort, filter,
aggregate, retype, add a column — touches one column across every row, and
because a column is the only place a type can be stated once instead of
once per cell.

This interface declares NO functions, which is the whole of its cost: it
exists so every guest is generated the SAME table types rather than
inventing its own. Values still travel as `values.value` trees; these types
are what both ends encode to and decode from, and the host's JSON Schema
projection of `ty-table` is what an agent generates against.