locals_without_parens = [
  websocket: 2
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  import_deps: [:plug],
  export: [
    locals_without_parens: locals_without_parens
  ]
]
