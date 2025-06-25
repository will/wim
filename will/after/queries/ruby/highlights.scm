; extends
((string) @spell (#match? @spell " "))
((interpolation) @nospell (#set! priority 105))
((comment) @comment.todo (#eq? @comment.todo "# :nocov:"))
