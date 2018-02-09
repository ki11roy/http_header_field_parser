ragel -Z -T0 -o parse_header_field.go parse_header_field.rl
go build -o parse_header_field.exe parse_header_field.go
ragel -Vp parse_header_field.rl -o parse_header_field.dot
dot parse_header_field.dot -Tpng -o parse_header_field.png
parse_header_field.exe