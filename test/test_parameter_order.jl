aa = [3, 7, 5, 4, 6]
bb = sortperm(aa, rev = true)
bb == [2, 5, 3, 4, 1]
cc = aa[bb]
ff = sortperm(bb)
dd = [5, 1, 3, 4, 2]
dd == ff
cc[dd] == aa
cc[ff] == aa
