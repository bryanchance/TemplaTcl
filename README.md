# TemplaTcl

[TemplaTcl](https://wiki.tcl.tk/18175): a Tcl template engine

The engine works by converting a template (which is a string, or a file)
into a Tcl script, and then running it. Nearly each line of text encountered
will be returned as is. The exception is text between <% ... %> which is
treated as Tcl code (the eval happens in a safe interp,
see [Safe Interps](https://wiki.tcl.tk/4204)).

I clone the source code and modify for myself purpose.

Notice:  
TemplaTcl do not work at Tcl 8.6.1.
