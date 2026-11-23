"""Merge ASAP7 per-cell-group Liberty files into one library.

usage: merge_lib.py <out.lib> <library-name> <in.lib>...

The header (everything before the first `cell (`) comes from the first input in
sorted order, with its library name replaced; the cells of every input follow.
Sorting happens here so callers need not agree on a shell locale.

Header table templates are the exception to first-header-wins. A Liberty table
group references its template by name (`cell_rise (delay_template_7x7)`), and
the template is defined in the table's own input header -- the ASAP7 RVT NLDM
groups do not agree on template names (SEQ 220123 uses `delay_template_7x7`,
the 211120/220122 groups `delay_template_7x7_x1`), so a template defined only
by a later input was dropped together with every table referencing it: OpenSTA
logs STA-1253 ("table template ... not found") and leaves the arc with no delay
model. Top-level `lu_table_template` / `power_lut_template` groups are
therefore collected from every input and unioned by name into the merged
header; the same name with different content in two inputs is an error naming
the template and both files, never a silent first-wins -- the rule of klt's
merge_liberty (klayout-tools#4242), ported here so the flow stays stdlib-only.
"""
import re
import sys

TEMPLATE_KINDS = ("lu_table_template", "power_lut_template")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def die(msg):
    sys.stderr.write("merge_lib.py: %s\n" % msg)
    sys.exit(1)


def _tokens(text):
    """Yield (token, start, end) for identifiers, string literals, braces and
    parens; comments are skipped whole, every other character alone."""
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in " \t\r\n":
            i += 1
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            if j >= n:
                die("unterminated string literal in a header")
            yield text[i : j + 1], i, j + 1
            i = j + 1
        elif c == "/" and text[i + 1 : i + 2] == "*":
            j = text.find("*/", i + 2)
            if j < 0:
                die("unterminated comment in a header")
            i = j + 2
        else:
            m = IDENT.match(text, i)
            if m:
                yield m.group(), m.start(), m.end()
                i = m.end()
            else:
                if c in "{}()":
                    yield c, i, i + 1
                i += 1


def _templates(header):
    """The header's top-level template groups as [(name, group text)]."""
    toks = list(_tokens(header))
    found, k, depth = [], 0, 0
    while k < len(toks):
        tok, pos, _ = toks[k]
        if tok == "{":
            depth += 1
        elif tok == "}":
            depth -= 1
        elif (
            depth == 1
            and tok in TEMPLATE_KINDS
            and k + 4 < len(toks)
            and toks[k + 1][0] == "("
            and toks[k + 2][0] not in "{}()"
            and toks[k + 3][0] == ")"
            and toks[k + 4][0] == "{"
        ):
            d, j = 0, k + 4
            while j < len(toks):
                if toks[j][0] == "{":
                    d += 1
                elif toks[j][0] == "}":
                    d -= 1
                    if d == 0:
                        break
                j += 1
            if j == len(toks):
                die("unbalanced braces in a %s group" % tok)
            found.append((toks[k + 2][0], header[pos : toks[j][2]]))
            k = j + 1
            continue
        k += 1
    return found


def main():
    out, name, *files = sys.argv[1:]
    if not files:
        die("usage: merge_lib.py <out.lib> <library-name> <in.lib>...")
    header, cells, extra = None, [], []
    seen = {}
    for i, f in enumerate(sorted(files)):
        t = open(f, encoding="utf-8").read()
        m = re.search(r"^\s*cell\s*\(", t, re.M)
        if not m:
            die("%s defines no cell" % f)
        for tname, raw in _templates(t[: m.start()]):
            norm = " ".join(tok for tok, _, _ in _tokens(raw))
            known = seen.get(tname)
            if known is None:
                seen[tname] = (norm, raw, f)
                if i:
                    extra.append(raw)
            elif known[0] != norm:
                die(
                    "template '%s' differs between '%s' and '%s'"
                    % (tname, known[2], f)
                )
        if i == 0:
            header = re.sub(r"library\s*\([^)]*\)", "library (%s)" % name, t[: m.start()], count=1)
        body = t[m.start():].rstrip()
        assert body.endswith("}"), f
        cells.append(body[:-1].rstrip() + "\n")
    if extra:
        header = header.rstrip() + "\n" + "\n".join(extra) + "\n"
    open(out, "w", encoding="utf-8").write(header + "".join(cells) + "}\n")


main()
