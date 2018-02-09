// -*-go-*-
//
// Parses HTTP 1.1 header field.
//
// To compile:
//
//   ragel -Z -T0 -o parse_header_field.go parse_header_field.rl
//   go build -o parse_header_field parse_header_field.go
//   ./parse_header_field
//
// To show a diagram of your state machine:
//
//   ragel -V -Z -p -o parse_header_field.dot parse_header_field.rl
//   xdot parse_header_field.dot
//

package main

import (
    "os"
    "fmt"
    "log"
    "regexp"
    "strings"
    "io"
    "io/ioutil"
)
var (
    Trace   *log.Logger
    Info    *log.Logger
    Warning *log.Logger
    Error   *log.Logger
)

func InitLogger(
    traceHandle io.Writer,
    infoHandle io.Writer,
    warningHandle io.Writer,
    errorHandle io.Writer) {

    Trace = log.New(traceHandle, "TRACE: ", 0)

    Info = log.New(infoHandle, "INFO: ", 0)

    Warning = log.New(warningHandle, "WARNING: ", 0)

    Error = log.New(errorHandle, "ERROR: ", 0)
}

%%{
    machine parse_header_field;
    write data;
}%%

func ParseHeaderField(data string, silent bool) (name string, value string, err error) {
    cs, p, pe := 0, 0, len(data)
    var value_start int = 0
    var name_start int = 0
    var content int = 0

    %%{
        action name_start { 
            Trace.Println("name_start", p)
            name_start = p 
        }
        action write_name { 
            Trace.Printf("write_name [%s]\n", data[name_start:p])
            name = data[name_start:p]
        }
        action done { 
            Trace.Printf("done [%s]\n", data[value_start:content])
            value = data[value_start:content]
        }
        action ows1 { 
            Trace.Println("ows1", p)
        }
        action ows2 { 
            Trace.Println("ows2", p)
        }
        action value_start { 
            Trace.Println("value_start", p)
            value_start = p 
        }
        action value_advance { 
            Trace.Println("value_advance", p)
            content = p + 1
        }

        crlf = "\r" "\n";
        ows = (" " | "\t")*;
        rws = (" " | "\t")+;

        vchar = 0x21..0x7e;

        obs_fold = crlf (" " | "\t")+;
        obs_text = 0x80..0xFF;

        field_vchar = vchar | obs_text;
        field_content = field_vchar (rws field_vchar)?;

        http_ctl = cntrl | 127;
        http_separator = ( "(" | ")" | "<" | ">" | "@" | "," | ";" | ":" | "\\" | "\"" | "/" | "[" | "]" | "?" | "=" | "{" | "}" | " " | "\t");
        token = ascii -- ( http_ctl | http_separator );

        field_name = token+ >name_start %write_name;

        field_value = (
        start: (
            ows @ows1 -> start |
            (field_content | obs_fold) @value_start ->one |
            '' -> final
        ),
        one: (
            ows @ows2 -> final |
            (field_content | obs_fold) @value_advance ->one
        ));

        main := field_name ":" ows field_value ows crlf @done;

        write init;
        write exec;
    }%%
    
    Trace.Printf("source\n[%s]\nresult\n[%s: %s]\n\n", data, name, value)

    if cs < parse_header_field_first_final {
        if !silent {
            Error.Println("parse_header_field: there was an error:", cs, "<", parse_header_field_first_final)
            Error.Print(data)
            Error.Print(strings.Repeat(" ", p), "^")
        }
        return name, value, fmt.Errorf("there was an error")
    }

    return name, value, nil
}

type parseHeaderFieldTest struct {
    source string
    name string
    value string
    shouldFail bool
}

var parseHeaderFieldTests = []parseHeaderFieldTest{
    parseHeaderFieldTest{"Host:   789   \r\n", "Host", "789", false},
    parseHeaderFieldTest{"Host:   789\r\n", "Host", "789", false},
    parseHeaderFieldTest{"Host:789\r\n", "Host", "789", false},
    parseHeaderFieldTest{"Host: 123     456\r\n", "Host", "123     456", false},
    parseHeaderFieldTest{"Host:\r\n", "Host", "", false},
    parseHeaderFieldTest{"Host: 789\r\n 0\r\n", "Host", "789\r\n 0", false},
    parseHeaderFieldTest{"Host: 789\r\n 0\r\n\t0\r\n", "Host", "789\r\n 0\r\n\t0", false},
    parseHeaderFieldTest{"Host:  00 333 45  \r\n", "Host", "00 333 45", false},
    parseHeaderFieldTest{"Host: 0 1 2\r\n", "Host", "0 1 2", true},
}

var crlf = regexp.MustCompile("\r\n")
var tab = regexp.MustCompile("\t")

func ReplaceInvisibles(src string) string {
    return tab.ReplaceAllString(crlf.ReplaceAllString(src, "\\r\\n"), "\\t")
}

func main() {
    InitLogger(ioutil.Discard, os.Stdout, os.Stdout, os.Stderr)
    
    var res int = 0
    for _, test := range parseHeaderFieldTests {
        var name, value, err = ParseHeaderField(test.source, test.shouldFail)
        if test.shouldFail && err != nil { 
            Info.Printf("[%s] -> [X]\n", ReplaceInvisibles(test.source))
            continue 
        }
        if name != test.name {
            Error.Printf("FAIL ParseHeaderField(%#v) %#v %#v\n", test.source, test.name, name)
            res = 1
        }
        if value != test.value {
            Error.Printf("FAIL ParseHeaderField(%#v) %#v %#v\n", test.source, test.value, value)
            res = 1
        }

        Info.Printf("[%s] -> [%s:%s]\n", ReplaceInvisibles(test.source), name, ReplaceInvisibles(value))
    }
    os.Exit(res)
}