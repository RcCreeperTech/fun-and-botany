package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:flags"
import "core:odin/ast"
import "core:odin/parser"

Options :: struct {
    package_path: string `args:"pos=0,required" usage:"The path to the Odin package you want to scan"`,
    verbose:      bool   `args:"name=v" usage:"Print the file location where the procedure was found"`,
    filter:       string `args:"name=f" usage:"Filter output by checking if the name or signature contains this string"`,
}

main :: proc() {
    opts: Options
    flags.parse_or_exit(&opts, os.args)

    fmt.printf("Scanning package at: %s\n", opts.package_path)
    if opts.filter != "" {
        fmt.printf("Filtering by: '%s'\n", opts.filter)
    }
    fmt.println("==================================================")

    pkg, ok := parser.parse_package_from_path(opts.package_path)
    if !ok {
        fmt.eprintf("Error: Failed to parse package at path '%s'\n", opts.package_path)
        os.exit(1)
    }

    for file_name, file in pkg.files {
        for decl in file.decls {
            if v_decl, is_v_decl := decl.derived.(^ast.Value_Decl); is_v_decl {
                if len(v_decl.values) > 0 {
                    if proc_lit, is_proc := v_decl.values[0].derived.(^ast.Proc_Lit); is_proc {
                        for name in v_decl.names {
                            if ident, is_ident := name.derived.(^ast.Ident); is_ident {

                                start := proc_lit.type.pos.offset
                                end   := proc_lit.type.end.offset

                                if start >= 0 && end <= len(file.src) && start <= end {
                                    signature := file.src[start:end]

                                    // If a filter string was provided, check for substring matches
                                    if opts.filter != "" {
                                        name_match := strings.contains(ident.name, opts.filter)
                                        sig_match  := strings.contains(signature, opts.filter)

                                        // Skip printing if neither the name nor the signature contains the filter string
                                        if !name_match && !sig_match {
                                            continue
                                        }
                                    }

                                    if opts.verbose {
                                        fmt.printf("%s :: %s \t(found in %s)\n", ident.name, signature, file_name)
                                    } else {
                                        fmt.printf("%s :: %s\n", ident.name, signature)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
