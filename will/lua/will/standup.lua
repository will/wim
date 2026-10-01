--- Renders chosen sections of a norg buffer as plain text for a Slack standup thread.
---
--- Slack's default composer converts markup as it is typed rather than when it is
--- pasted, which leaves pasted markup literal. This output therefore assumes "Format
--- messages with markup" (Preferences > Advanced > Input options) is on, so Slack parses
--- the message on send: `*bold*`, `_italic_`, `~strike~`, backtick code, `>` quotes and
--- `[label](url)` links. The `<url|label>` form is the API's, and prints verbatim here.
local M = {}

M.config = {
  --- Bullet per nesting depth; the last entry repeats for anything deeper.
  bullets = { "• ", "◦ ", "‣ " },
  indent = "    ",

  --- Prefix per norg task state. Set one to "" to keep the item but drop its marker.
  todo_markers = {
    undone = "☐ ",
    done = "☑ ",
    pending = "◐ ",
    on_hold = "⏸ ",
    cancelled = "☒ ",
    urgent = "❗ ",
    uncertain = "❔ ",
    recurring = "🔁 ",
  },
}

--- norg attached modifier -> the Slack delimiter that replaces its `_open`/`_close`.
--- An empty string strips the markup, keeping the text.
local slack_delimiters = {
  bold = "*",
  italic = "_",
  underline = "_",
  strikethrough = "~",
  verbatim = "`",
  inline_math = "`",
  spoiler = "",
  superscript = "",
  subscript = "",
}

--- The sections flagged for the standup, in the order `will.journal` lays them out.
--- A section that is absent from the entry, or present with no content under it, is
--- dropped rather than emitted as a bare header.
--- @return string[]
local function sections()
  local names = {}
  for _, section in ipairs(require("will.journal").sections()) do
    if section.standup then names[#names + 1] = section.name end
  end
  return names
end

local function field(node, name)
  local children = node:field(name)
  return children[1]
end

local function field_text(node, name, buf)
  local child = node and field(node, name)
  return child and vim.trim(vim.treesitter.get_node_text(child, buf)) or nil
end

--- Web links become `[label](url)`, or stay bare when there is no label for Slack to show
--- instead; every other target (headings, files, anchors) has no URL worth pasting into
--- Slack, so only its label survives.
--- Shared by `link` and `anchor_definition`, which differ only in child order.
local function link_text(node, buf)
  local location, description
  for child in node:iter_children() do
    local kind = child:type()
    if kind == "link_location" then
      location = child
    elseif kind == "link_description" then
      description = child
    end
  end

  local label = field_text(description, "text", buf)
  if not location then return label or "" end

  local target = field(location, "type")
  local text = field_text(location, "text", buf) or field_text(location, "file", buf)

  if target and target:type() == "link_target_url" and text then
    return label and ("[" .. label .. "](" .. text .. ")") or text
  end
  return label or text or ""
end

--- A `paragraph_segment` never spans lines, so inline markup is rewritten as byte edits
--- on its source text, applied right to left so the earlier offsets stay valid. Node
--- types with no rule fall through and keep their original text.
local function render_segment(node, buf)
  local row, start_col, _, end_col = node:range()
  local text = vim.api.nvim_buf_get_lines(buf, row, row + 1, true)[1]:sub(start_col + 1, end_col)
  local edits = {}

  local function replace(target, with)
    local target_row, from, _, to = target:range()
    if target_row == row then edits[#edits + 1] = { from = from - start_col, to = to - start_col, text = with } end
  end

  local function collect(current)
    local kind = current:type()
    if kind == "link" or kind == "anchor_definition" then return replace(current, link_text(current, buf)) end
    if kind == "inline_comment" then return replace(current, "") end

    local delimiter = slack_delimiters[kind]
    for child in current:iter_children() do
      local child_kind = child:type()
      if delimiter and (child_kind == "_open" or child_kind == "_close") then
        replace(child, delimiter)
      else
        collect(child)
      end
    end
  end

  collect(node)
  table.sort(edits, function(a, b) return a.from > b.from end)
  for _, edit in ipairs(edits) do
    text = text:sub(1, edit.from) .. edit.text .. text:sub(edit.to + 1)
  end
  return text
end

local function bullet(depth)
  local bullets = M.config.bullets
  return bullets[math.min(depth + 1, #bullets)]
end

local function push(out, depth, text) out[#out + 1] = text == "" and "" or M.config.indent:rep(depth) .. text end

local function todo_marker(state)
  for child in state:iter_children() do
    local name = child:type():match "^todo_item_(.+)$"
    if name then return M.config.todo_markers[name] or "" end
  end
  return ""
end

local render_block, render_children

--- The marker, any task state and the item's first text line share one output line;
--- wrapped continuation lines and anything nested sit one level deeper.
local function render_item(node, buf, depth, out, marker)
  local state = field(node, "state")
  if state then marker = marker .. todo_marker(state) end

  --- the item's own text, as opposed to a later paragraph in the same item
  local text
  for child, name in node:iter_children() do
    if not text and name == "content" and child:type() == "paragraph" then text = child end
  end

  local pending = marker
  if text then
    for segment in text:iter_children() do
      if segment:type() == "paragraph_segment" then
        local line = vim.trim(render_segment(segment, buf))
        push(out, pending and depth or depth + 1, pending and pending .. line or line)
        pending = nil
      end
    end
  end
  if pending then push(out, depth, vim.trim(pending)) end

  render_children(node, buf, depth + 1, out, text)
end

--- `@code` becomes a fenced block, which Slack renders as one; other ranged tags
--- (`@document.meta` and friends) carry nothing a standup wants.
local function render_verbatim(node, buf, depth, out)
  if field_text(node, "name", buf) ~= "code" then return end

  local language = ""
  for child in node:iter_children() do
    if child:type() == "tag_parameters" then language = vim.treesitter.get_node_text(child, buf) end
  end

  push(out, depth, "```" .. language)
  local content = field(node, "content")
  if content then
    -- read the source lines rather than the node text, whose first line already has the
    -- indent stripped; the tag's own column is the block's base indent to remove
    local _, column = node:range()
    local first_row, _, last_row, last_col = content:range()
    local last = last_col == 0 and last_row or last_row + 1
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, first_row, last, false)) do
      out[#out + 1] = line:sub(column + 1)
    end
  end
  push(out, depth, "```")
end

--- Dispatches a node's block children, numbering ordered list items that share a parent.
--- `skip` is the node already rendered onto an enclosing item's marker line.
render_children = function(node, buf, depth, out, skip)
  local ordered = 0
  for child, name in node:iter_children() do
    local kind = child:type()
    if skip and child:equal(skip) then
      ordered = 0
    elseif kind:match "^ordered_list%d$" then
      ordered = ordered + 1
      render_item(child, buf, depth, out, ordered .. ". ")
    elseif kind:match "^unordered_list%d$" then
      ordered = 0
      render_item(child, buf, depth, out, bullet(depth))
    elseif kind:match "^quote%d$" then
      render_item(child, buf, depth, out, "> ")
    elseif name ~= "title" and name ~= "state" and not kind:match "_prefix$" then
      render_block(child, buf, depth, out)
    end
  end
end

render_block = function(node, buf, depth, out)
  local kind = node:type()

  if kind == "generic_list" or kind == "quote" then
    render_children(node, buf, depth, out)
  elseif kind:match "^heading%d$" then
    local title = field(node, "title")
    if title then push(out, depth, "*" .. vim.trim(render_segment(title, buf)) .. "*") end
    render_children(node, buf, depth, out)
  elseif kind == "paragraph" then
    for child in node:iter_children() do
      if child:type() == "paragraph_segment" then push(out, depth, vim.trim(render_segment(child, buf))) end
    end
  elseif kind == "ranged_verbatim_tag" then
    render_verbatim(node, buf, depth, out)
  elseif kind == "_paragraph_break" then
    out[#out + 1] = ""
  end
end

--- Headings by lower-cased title, first in document order winning, so an outer heading
--- takes precedence over a nested one of the same name.
local function headings(buf, root)
  local found = {}
  local function walk(node)
    for child in node:iter_children() do
      if child:type():match "^heading%d$" then
        local title = field_text(child, "title", buf)
        if title and not found[title:lower()] then found[title:lower()] = child end
      end
      walk(child)
    end
  end
  walk(root)
  return found
end

local function tidy(lines)
  local out = {}
  for _, line in ipairs(lines) do
    if line ~= "" or out[#out] ~= "" then out[#out + 1] = line end
  end
  while out[1] == "" do
    table.remove(out, 1)
  end
  while out[#out] == "" do
    table.remove(out)
  end
  return out
end

--- Everything above the first heading, which is where will.journal puts the entry's date.
--- Rendered through the same machinery as the sections, so a `@document.meta` block up
--- there is dropped the way it is everywhere else.
local function preamble(buf, root)
  local lines = {}
  for child in root:iter_children() do
    if child:type():match "^heading%d$" then break end
    render_block(child, buf, 0, lines)
  end
  return tidy(lines)
end

--- @return string[] lines of the Slack message, empty when no section had content
function M.render(buf)
  buf = buf and buf ~= 0 and buf or vim.api.nvim_get_current_buf()

  local ok, parser = pcall(vim.treesitter.get_parser, buf, "norg")
  if not ok or not parser then return {} end
  local root = parser:parse()[1]:root()
  local found = headings(buf, root)

  local message = {}
  for _, name in ipairs(sections()) do
    local node = found[name:lower()]
    if node then
      local body = {}
      for child, child_name in node:iter_children() do
        if child_name == "content" then render_block(child, buf, 0, body) end
      end

      body = tidy(body)
      if #body > 0 then
        if #message > 0 then message[#message + 1] = "" end
        message[#message + 1] = "*" .. name .. "*"
        vim.list_extend(message, body)
      end
    end
  end

  -- only once a section has earned the message: an untouched entry should copy nothing
  -- rather than a lone date. The first line carries the date, so it is bolded into a
  -- title; anything else written up there stays as it was typed.
  if #message > 0 then
    local lead = preamble(buf, root)
    if #lead > 0 then
      lead[1] = "*" .. lead[1] .. "*"
      lead[#lead + 1] = ""
      message = vim.list_extend(lead, message)
    end
  end
  return message
end

--- Renders the buffer into the system clipboard, leaving the buffer itself untouched.
--- @return string|nil the copied message
function M.copy(buf)
  local message = M.render(buf)
  if #message == 0 then
    vim.notify("Nothing to copy, no content under: " .. table.concat(sections(), ", "), vim.log.levels.WARN)
    return nil
  end

  local text = table.concat(message, "\n")
  vim.fn.setreg("+", text)
  vim.notify(text, vim.log.levels.INFO, { title = "Standup copied to clipboard" })
  return text
end

return M
