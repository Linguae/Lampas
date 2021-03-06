Lampas
======
Lampas is my first Lisp; currently its unique features include lambda shorthand, vector notation, continuations, and Lisp-style macros. 

Macros allow for codes to be specified that will manipulate any S-Expressions which they begin. That is, if `a` were a macro, any S-Expression led with `a` would be passed to the macro definition prior to evaluation; an example is below. 

Continuations were defined purely with macros. The general workflow of a continuation is to initiate a continuation statement with `begincc`, and then in the context of the statement, where the value of interest is present, to call `call/cc` with a lambda taking a continuation as a parameter. That continuation can then be set to a variable for later calling, and an initial value should be returned. Upon calling the continuation, values should be quoted (for now).

```scheme
[1 2 3]
" => (1 2 3)
"

({|x| (+ 1 x)} 5)
" => 6
"

(defmacro 
  (let name val body) 
  `((lambda (,name) ,body) ,val))
(let a 5 (cons a 2))
" => (5 2)
"

(define print 5)    
((lambda 
  (x) 
  (begincc 
    (write 
      (call/cc {|cc| (set! print cc) x}))))
5)
(print '(+ x 1))
"  => 5
"" => 6
"
```

Syntax
------
See examples of syntax in `src/test.lampas`. 

For macros, after beginning with a `define-rewriter` approach, wherein macros received each S-Expression in which they were embedded as arguments, I instead opted for `defmacro`. `defmacro` parses components as arguments, but the full power of `define-rewriter` could be easily rebuilt. My implementation of macros was pretty straight-forward, each `defmacro` defined a function in the usual environment with a distinct name. From there, each S-Expression is checked for a corresponding macro name. If one is found, the tail of the S-Expression is passed as argument to the defined function. This method keeps macros hygienic. This implementation may be improper, or perhaps it has too much overhead, but it was very easily implemented.

I have implemented another type of macro called `defenvmacro`. `defenvmacro` receives the environment, that is, the entire context of the passed expression, as a parameter. This gives the full power of the interpreter to macros, and a simple call to `eval` could thus pick up exactly where the expression left off. Why is this special? By this method the macro exists in both its context of creation via closures and the context of the expression via `env` + `eval`. This gives it the full power of the interpreter.

Compilation
-----------
Compile the source using GHC and the Existential flag.

```sh
$ ghc Main.hs -XExistentialQuantification
```

Or, if on a Unix machine, run the build script which will compile, test, and clean-up. Support for Windows will be added soon.

```sh
$ ./build.sh
```

Build Script
------------
For the build script to generate documentation, it requires node.js and docco. However, if this aspect is removed it merely requires GHC.

The build script generates documentation, compiles all sources, removes intermediary compilation files, and then runs the test suite. All test results are of the following form in the terminal.

```scheme
"# Output (= `Hello`)"
"Hello"
```

Where the asserted value is named with appropriate value in parenthesis. Tests serve to prevent unknown breaking of features.

Usage
-----
Then run the interpreter either with a program as a parameter or individually to fire up a REPL.

```sh
$ ./lampas
Lampas >>
```

```sh
$ ./lampas test.lampas
```

Include the library functions with the following.

```sh
(load "Prelude.lampas")
```

Todo
-----
- `,@` unquote-splicing
- `case` statements
- `currying`
- `continuations` - the last component of continuations that needs to be implemented is continuation of the stack, rather than the current mere re-evaluation of the expression. I think as an intermediary implementation I'll have `begincc` accept a variable number of expressions over which it will operate. Values are also immutable right now! The only solution I foresee existing for this is to overwrite the `set!`, `define`, etc. functions when performing the `evalenv`; this should not be too hard.
- `numerical tower`

References
----------
- This is very much thanks to the tutorial [Write Yourself a Scheme in 48 Hours](http://en.wikibooks.org/wiki/Write_Yourself_a_Scheme_in_48_Hours) by *Jonathan Tang*. It makes quite clear how to implement a language in Haskell, developing a REPL early on and building it up to a full-fledged Scheme.
- Fogus' [Caerbannog](https://github.com/fogus/caerbannog).
- An introduction to continuations in Scheme, [On Continuations](http://dunsmor.com/lisp/onlisp/onlisp_24.html).
- A discussion of macros in Scheme and Lisp, [On Macros](ftp://ftp.cs.utexas.edu/pub/garbage/cs345/schintro-v13/schintro_130.html)