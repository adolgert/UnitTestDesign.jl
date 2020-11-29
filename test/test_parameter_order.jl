using UnitTestDesign
ip232 = ipog([2, 3, 2], 2)
@test size(ip232) == (3, 6)
ip2324 = ipog([2, 3, 2, 4, 7, 2], 2)
@test size(ip2324) == (6, 28)

#res = ipog([2, 3, 2, 4, 4, 4, 4, 4, 4, 4, 4, 7, 2, 4, 5, 4, 4], 3)
