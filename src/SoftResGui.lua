RollFor = RollFor or {}
local m = RollFor

if m.SoftResGui then return end

local M                = {}
local hl               = m.colors.hl

---@diagnostic disable-next-line: undefined-global
local UIParent         = UIParent
---@diagnostic disable-next-line: undefined-global
local ChatFontNormal   = ChatFontNormal

local frame_backdrop   = {
  bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile     = true,
  tileSize = 32,
  edgeSize = 32,
  insets   = { left = 8, right = 8, top = 8, bottom = 8 }
}

local control_backdrop = {
  bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile     = true,
  tileSize = 16,
  edgeSize = 16,
  insets   = { left = 3, right = 3, top = 3, bottom = 3 }
}

local TABLE_FRAME_WIDTH  = 780
local TABLE_FRAME_HEIGHT = 540

local COL_PLAYER = 160
local COL_ITEM   = 280
local COL_TYPE   = 80
local COL_SRPLUS = 80

local MAP_COL_TYPE       = 45
local MAP_COL_RESERVE_ID = 80
local MAP_COL_RESERVE    = 240
local MAP_COL_MATCH_ID   = 80
local MAP_COL_MATCH      = 240
local MAP_COL_ROLLERS    = 55

local ROW_HEIGHT    = 18
local HEADER_HEIGHT = 22

local MAX_RETRIES    = 3
local RETRY_INTERVAL = 15

-- ---------------------------------------------------------------------------
-- Import frame (unchanged from original)
-- ---------------------------------------------------------------------------

local function create_import_frame( api, on_import, on_clear, on_cancel, on_dirty, use_item_names, on_use_item_names_toggled, on_show_mapping )
  local frame = m.create_backdrop_frame( api(), "Frame", "RollForSoftResLootFrame", UIParent )
  frame:Hide()
  frame:SetWidth( 565 )
  frame:SetHeight( 324 )
  frame:SetPoint( "CENTER", UIParent, "CENTER", 0, 0 )
  frame:EnableMouse()
  frame:SetMovable( true )
  frame:SetResizable( true )
  frame:SetFrameStrata( "DIALOG" )
  frame:SetBackdrop( frame_backdrop )
  frame:SetBackdropColor( 0, 0, 0, 1 )
  frame:SetMinResize( 400, 220 )
  frame:SetToplevel( true )

  local backdrop = m.create_backdrop_frame( api(), "Frame", nil, frame )
  backdrop:SetBackdrop( control_backdrop )
  backdrop:SetBackdropColor( 0, 0, 0 )
  backdrop:SetBackdropBorderColor( 0.4, 0.4, 0.4 )
  backdrop:SetPoint( "TOPLEFT",     frame, "TOPLEFT",     17,  -18 )
  backdrop:SetPoint( "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -17,  67 )

  local scroll_frame = api().CreateFrame( "ScrollFrame", "a@ScrollFrame@c", backdrop, "UIPanelScrollFrameTemplate" )
  scroll_frame:SetPoint( "TOPLEFT",     5,   -6 )
  scroll_frame:SetPoint( "BOTTOMRIGHT", -28,  6 )
  scroll_frame:EnableMouse( true )

  local scroll_child = api().CreateFrame( "Frame", nil, scroll_frame )
  scroll_frame:SetScrollChild( scroll_child )
  scroll_child:SetHeight( 2 )
  scroll_child:SetWidth( 2 )

  local editbox = api().CreateFrame( "EditBox", nil, scroll_child )
  editbox:SetPoint( "TOPLEFT", 0, 0 )
  editbox:SetHeight( 50 )
  editbox:SetWidth( 50 )
  editbox:SetMultiLine( true )
  editbox:SetTextInsets( 5, 5, 3, 3 )
  editbox:EnableMouse( true )
  editbox:SetAutoFocus( false )
  editbox:SetFontObject( ChatFontNormal )
  frame.editbox = editbox

  editbox:SetScript( "OnEscapePressed", function() editbox:ClearFocus() end )
  scroll_frame:SetScript( "OnMouseUp", function() editbox:SetFocus() end )

  local function fix_size()
    scroll_child:SetHeight( scroll_frame:GetHeight() )
    scroll_child:SetWidth( scroll_frame:GetWidth() )
    editbox:SetWidth( scroll_frame:GetWidth() )
  end

  scroll_frame:SetScript( "OnShow",        fix_size )
  scroll_frame:SetScript( "OnSizeChanged", fix_size )

  local cancel_button = api().CreateFrame( "Button", nil, frame, "UIPanelButtonTemplate" )
  cancel_button:SetScript( "OnClick", function()
    frame:Hide()
    editbox:SetText( on_cancel() or "" )
  end )
  cancel_button:SetPoint( "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -27, 17 )
  cancel_button:SetHeight( 20 )
  cancel_button:SetWidth( 80 )
  cancel_button:SetText( "Close" )

  local clear_button = api().CreateFrame( "Button", nil, frame, "UIPanelButtonTemplate" )
  clear_button:SetScript( "OnClick", function()
    editbox:SetText( "" )
    cancel_button:SetText( "Close" )
    on_clear()
  end )
  clear_button:SetPoint( "RIGHT", cancel_button, "LEFT", -10, 0 )
  clear_button:SetHeight( 20 )
  clear_button:SetWidth( 80 )
  clear_button:SetText( "Clear" )

  local import_button = api().CreateFrame( "Button", nil, frame, "UIPanelButtonTemplate" )
  frame.import_button = import_button
  import_button:SetScript( "OnClick", function()
    on_import( function() frame:Hide() end )
  end )
  import_button:SetPoint( "RIGHT", clear_button, "LEFT", -10, 0 )
  import_button:SetHeight( 20 )
  import_button:SetWidth( 100 )
  import_button:SetText( "Import!" )

  editbox:SetScript( "OnTextChanged", function()
    scroll_frame:UpdateScrollChildRect()
    on_dirty( import_button, clear_button, cancel_button )
  end )

  -- Toggle: match soft-reserved items to dropped loot by name instead of by item id alone.
  local use_names_checkbox = api().CreateFrame( "CheckButton", nil, frame, "UICheckButtonTemplate" )
  use_names_checkbox:SetWidth( 20 )
  use_names_checkbox:SetHeight( 20 )
  use_names_checkbox:SetPoint( "BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 41 )
  use_names_checkbox:SetScript( "OnClick", function()
    local checked = use_names_checkbox:GetChecked() and true or false
    if on_use_item_names_toggled then on_use_item_names_toggled( checked ) end
  end )
  frame.use_names_checkbox = use_names_checkbox

  local use_names_label = frame:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
  use_names_label:SetPoint( "LEFT", use_names_checkbox, "RIGHT", 0, 1 )
  use_names_label:SetTextColor( 1, 1, 1, 1 )
  use_names_label:SetText( "Heroic item matching" )

  local use_names_help = frame:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
  use_names_help:SetPoint( "LEFT", use_names_label, "RIGHT", 6, 0 )
  use_names_help:SetTextColor( 0.7, 0.7, 0.7, 1 )
  use_names_help:SetText( "(name-based)" )

  local mapping_button = api().CreateFrame( "Button", nil, frame, "UIPanelButtonTemplate" )
  mapping_button:SetScript( "OnClick", function()
    if on_show_mapping then on_show_mapping() end
  end )
  mapping_button:SetPoint( "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -27, 41 )
  mapping_button:SetHeight( 20 )
  mapping_button:SetWidth( 130 )
  mapping_button:SetText( "Inspect Mapping" )

  frame:SetScript( "OnShow", function()
    cancel_button:SetText( "Close" )
    on_dirty( import_button, clear_button, cancel_button )
    if use_item_names then use_names_checkbox:SetChecked( use_item_names.is_enabled() ) end
  end )

  do
    local cursor_offset, cursor_height
    local idle_time

    local function fix_scroll( _, elapsed )
      if cursor_offset and cursor_height then
        idle_time = 0
        local height = scroll_frame:GetHeight()
        local range  = scroll_frame:GetVerticalScrollRange()
        local scroll = scroll_frame:GetVerticalScroll()
        cursor_offset = -cursor_offset

        while cursor_offset < scroll do
          scroll = scroll - (height / 2)
          if scroll < 0 then scroll = 0 end
          scroll_frame:SetVerticalScroll( scroll )
        end

        while cursor_offset + cursor_height > scroll + height and scroll < range do
          scroll = scroll + (height / 2)
          if scroll > range then scroll = range end
          scroll_frame:SetVerticalScroll( scroll )
        end
      elseif not idle_time or idle_time > 2 then
        frame:SetScript( "OnUpdate", nil )
        idle_time = nil
      else
        idle_time = idle_time + elapsed
      end

      cursor_offset = nil
    end

    editbox:SetScript( "OnCursorChanged", function( _, _, y, _, h )
      cursor_offset, cursor_height = y, h
      if not idle_time then
        frame:SetScript( "OnUpdate", fix_scroll )
      end
    end )
  end

  local label = frame:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
  label:SetPoint( "BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 22 )
  label:SetTextColor( 1, 1, 1, 1 )

  local realm = GetRealmName()
  local sr_website
  if m.vanilla then
    sr_website = "raidres.fly.dev"
  else
    sr_website = "softres.it"
  end

  label:SetText( string.format( "%s      %s %s", m.colors.blue( "rollfor_cool" ), hl( sr_website ), "data import" ) )

  ---@diagnostic disable-next-line: undefined-global
  table.insert( UISpecialFrames, "RollForSoftResLootFrame" )
  return frame
end

-- ---------------------------------------------------------------------------
-- Table frame
-- ---------------------------------------------------------------------------

local function create_table_frame( api, on_back )
  local frame = m.create_backdrop_frame( api(), "Frame", "RollForSoftResTableFrame", UIParent )
  frame:Hide()
  frame:SetWidth( TABLE_FRAME_WIDTH )
  frame:SetHeight( TABLE_FRAME_HEIGHT )
  frame:SetPoint( "CENTER", UIParent, "CENTER", 0, 0 )
  frame:EnableMouse()
  frame:SetMovable( true )
  frame:SetFrameStrata( "DIALOG" )
  frame:SetBackdrop( frame_backdrop )
  frame:SetBackdropColor( 0, 0, 0, 1 )
  frame:SetToplevel( true )

  local close_button = api().CreateFrame( "Button", nil, frame, "UIPanelCloseButton" )
  close_button:SetPoint( "TOPRIGHT", frame, "TOPRIGHT", 0, 0 )
  close_button:SetScript( "OnClick", function() frame:Hide() end )

  local title = frame:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
  title:SetPoint( "TOPLEFT", frame, "TOPLEFT", 20, -14 )
  title:SetTextColor( 1, 1, 1, 1 )
  title:SetText( string.format( "%s  -  Soft / Hard Reserves", m.colors.blue( "rollfor_cool" ) ) )

  -- Inner backdrop for the table area
  local inner = m.create_backdrop_frame( api(), "Frame", nil, frame )
  inner:SetBackdrop( control_backdrop )
  inner:SetBackdropColor( 0, 0, 0 )
  inner:SetBackdropBorderColor( 0.4, 0.4, 0.4 )
  inner:SetPoint( "TOPLEFT",     frame, "TOPLEFT",     17,  -32 )
  inner:SetPoint( "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -17,  43 )

  -- Column header bar
  local header_bar = api().CreateFrame( "Frame", nil, inner )
  header_bar:SetPoint( "TOPLEFT",  inner, "TOPLEFT",  4,   -4 )
  header_bar:SetPoint( "TOPRIGHT", inner, "TOPRIGHT", -22, -4 )  -- leave room for scrollbar
  header_bar:SetHeight( HEADER_HEIGHT )

  local header_bg = header_bar:CreateTexture( nil, "BACKGROUND" )
  header_bg:SetAllPoints()
  header_bg:SetTexture( 0.15, 0.15, 0.15, 1 )

  local function make_header_cell( label, x, width )
    local fs = header_bar:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
    fs:SetPoint( "LEFT", header_bar, "LEFT", x + 4, 0 )
    fs:SetWidth( width - 8 )
    fs:SetJustifyH( "LEFT" )
    fs:SetText( m.colors.white( label ) )
  end

  make_header_cell( "Player", 0,                                     COL_PLAYER )
  make_header_cell( "Item",   COL_PLAYER,                            COL_ITEM )
  make_header_cell( "Type",   COL_PLAYER + COL_ITEM,                 COL_TYPE )
  make_header_cell( "SR+",    COL_PLAYER + COL_ITEM + COL_TYPE,      COL_SRPLUS )

  -- Scroll frame for rows
  local scroll_frame = api().CreateFrame( "ScrollFrame", "RollForSRTableScroll", inner, "UIPanelScrollFrameTemplate" )
  scroll_frame:SetPoint( "TOPLEFT",     header_bar, "BOTTOMLEFT",  0,   -2 )
  scroll_frame:SetPoint( "BOTTOMRIGHT", inner,      "BOTTOMRIGHT", -22,  4 )

  local scroll_child = api().CreateFrame( "Frame", nil, scroll_frame )
  scroll_frame:SetScrollChild( scroll_child )
  scroll_child:SetWidth( 1 )
  scroll_child:SetHeight( 1 )

  -- Back to Import button
  local back_button = api().CreateFrame( "Button", nil, frame, "UIPanelButtonTemplate" )
  back_button:SetPoint( "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -27, 17 )
  back_button:SetHeight( 20 )
  back_button:SetWidth( 120 )
  back_button:SetText( "Back to Import" )
  back_button:SetScript( "OnClick", function()
    frame:Hide()
    on_back()
  end )

  -- Status label (shown during item link fetching)
  local status_label = frame:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
  status_label:SetPoint( "BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 22 )
  status_label:SetTextColor( 0.7, 0.7, 0.7, 1 )
  frame.status_label = status_label

  -- Row pool
  local row_pool = {}
  local hr_collapsed = true
  local last_hr_rows = {}
  local last_sr_rows = {}

  local function acquire_row( index )
    local row = row_pool[ index ]
    if not row then
      row = api().CreateFrame( "Frame", nil, scroll_child )
      row:SetHeight( ROW_HEIGHT )

      local bg = row:CreateTexture( nil, "BACKGROUND" )
      bg:SetAllPoints()
      row.bg = bg

      local function make_cell( x, w )
        local fs = row:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
        fs:SetPoint( "LEFT", row, "LEFT", x + 4, 0 )
        fs:SetWidth( w - 8 )
        fs:SetJustifyH( "LEFT" )
        return fs
      end

      row.cell_player = make_cell( 0,                                  COL_PLAYER )
      row.cell_item   = make_cell( COL_PLAYER,                         COL_ITEM )
      row.cell_type   = make_cell( COL_PLAYER + COL_ITEM,              COL_TYPE )
      row.cell_srplus = make_cell( COL_PLAYER + COL_ITEM + COL_TYPE,   COL_SRPLUS )

      row_pool[ index ] = row
    end
    return row
  end

  local function render_rows()
    local total_width = scroll_frame:GetWidth()
    local row_index = 0

    -- HR section toggle header (only shown when there are HR items)
    if #last_hr_rows > 0 then
      row_index = row_index + 1
      local toggle_row = acquire_row( row_index )
      toggle_row:ClearAllPoints()
      toggle_row:SetPoint( "TOPLEFT", scroll_child, "TOPLEFT", 0, -( (row_index - 1) * ROW_HEIGHT ) )
      toggle_row:SetWidth( total_width )
      toggle_row:Show()
      toggle_row:EnableMouse( true )

      toggle_row.bg:SetTexture( 0.20, 0.08, 0.08, 1 )
      toggle_row.cell_player:SetWidth( COL_PLAYER + COL_ITEM + COL_TYPE + COL_SRPLUS - 8 )
      toggle_row.cell_player:SetText( string.format( "%s  %s",
        m.colors.red( string.format( "Hard Reserves (%d)", #last_hr_rows ) ),
        hr_collapsed and m.colors.grey( "[+]" ) or m.colors.grey( "[-]" ) ) )
      toggle_row.cell_item:SetText( "" )
      toggle_row.cell_type:SetText( "" )
      toggle_row.cell_srplus:SetText( "" )

      toggle_row:SetScript( "OnMouseUp", function()
        hr_collapsed = not hr_collapsed
        render_rows()
      end )

      -- HR item rows (only shown when expanded)
      if not hr_collapsed then
        for _, data in ipairs( last_hr_rows ) do
          row_index = row_index + 1
          local row = acquire_row( row_index )
          row:ClearAllPoints()
          row:SetPoint( "TOPLEFT", scroll_child, "TOPLEFT", 0, -( (row_index - 1) * ROW_HEIGHT ) )
          row:SetWidth( total_width )
          row:Show()
          row:EnableMouse( false )

          row.bg:SetTexture( 0.25, 0.10, 0.10, 1 )
          row.cell_player:SetWidth( COL_PLAYER + COL_ITEM + COL_TYPE + COL_SRPLUS - 8 )
          row.cell_player:SetText( string.format( "%s  —  %s",
            data.item_link or m.colors.grey( tostring( data.item_id ) ),
            m.colors.red( "Hard Reserved" ) ) )
          row.cell_item:SetText( "" )
          row.cell_type:SetText( "" )
          row.cell_srplus:SetText( "" )
        end
      end
    end

    -- SR rows (always visible)
    local sr_row_index = 0
    for _, data in ipairs( last_sr_rows ) do
      row_index = row_index + 1
      sr_row_index = sr_row_index + 1
      local row = acquire_row( row_index )
      row:ClearAllPoints()
      row:SetPoint( "TOPLEFT", scroll_child, "TOPLEFT", 0, -( (row_index - 1) * ROW_HEIGHT ) )
      row:SetWidth( total_width )
      row:Show()
      row:EnableMouse( false )

      if sr_row_index % 2 == 0 then
        row.bg:SetTexture( 0.10, 0.10, 0.10, 0.8 )
      else
        row.bg:SetTexture( 0.06, 0.06, 0.06, 0.8 )
      end

      row.cell_player:SetWidth( COL_PLAYER - 8 )
      row.cell_player:SetText( data.player_text or "" )
      row.cell_item:SetText( data.item_link or m.colors.grey( tostring( data.item_id ) ) )
      row.cell_type:SetText( m.colors.blue( "SR" ) )
      row.cell_srplus:SetText( data.sr_plus and tostring( data.sr_plus ) or m.colors.grey( "—" ) )
    end

    -- Hide any surplus pooled rows
    for i = row_index + 1, #row_pool do
      if row_pool[ i ] then row_pool[ i ]:Hide() end
    end

    scroll_child:SetHeight( math.max( 1, row_index * ROW_HEIGHT ) )
    scroll_child:SetWidth( math.max( 1, total_width ) )
    scroll_frame:UpdateScrollChildRect()
    scroll_frame:SetVerticalScroll( 0 )
  end

  -- Populate accepts separate hr and sr row lists.
  -- Always resets to collapsed on a fresh data load.
  local function populate( hr_rows, sr_rows )
    last_hr_rows = hr_rows
    last_sr_rows = sr_rows
    hr_collapsed = true
    render_rows()
  end

  frame.populate = populate

  ---@diagnostic disable-next-line: undefined-global
  table.insert( UISpecialFrames, "RollForSoftResTableFrame" )
  return frame
end

-- ---------------------------------------------------------------------------
-- Heroic item matching frame
-- ---------------------------------------------------------------------------

local function create_mapping_frame( api, on_back, use_item_names, on_use_item_names_toggled, on_refresh )
  local frame = m.create_backdrop_frame( api(), "Frame", "RollForSoftResMappingFrame", UIParent )
  frame:Hide()
  frame:SetWidth( TABLE_FRAME_WIDTH )
  frame:SetHeight( TABLE_FRAME_HEIGHT )
  frame:SetPoint( "CENTER", UIParent, "CENTER", 0, 0 )
  frame:EnableMouse()
  frame:SetMovable( true )
  frame:SetFrameStrata( "DIALOG" )
  frame:SetBackdrop( frame_backdrop )
  frame:SetBackdropColor( 0, 0, 0, 1 )
  frame:SetToplevel( true )

  local close_button = api().CreateFrame( "Button", nil, frame, "UIPanelCloseButton" )
  close_button:SetPoint( "TOPRIGHT", frame, "TOPRIGHT", 0, 0 )
  close_button:SetScript( "OnClick", function() frame:Hide() end )

  local title = frame:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
  title:SetPoint( "TOPLEFT", frame, "TOPLEFT", 20, -14 )
  title:SetTextColor( 1, 1, 1, 1 )
  title:SetText( string.format( "%s  -  Heroic Item Matching", m.colors.blue( "rollfor_cool" ) ) )

  local enabled_checkbox = api().CreateFrame( "CheckButton", nil, frame, "UICheckButtonTemplate" )
  enabled_checkbox:SetWidth( 20 )
  enabled_checkbox:SetHeight( 20 )
  enabled_checkbox:SetPoint( "TOPLEFT", frame, "TOPLEFT", 18, -34 )
  enabled_checkbox:SetScript( "OnClick", function()
    local checked = enabled_checkbox:GetChecked() and true or false
    if on_use_item_names_toggled then on_use_item_names_toggled( checked ) end
    if on_refresh then on_refresh() end
  end )

  local enabled_label = frame:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
  enabled_label:SetPoint( "LEFT", enabled_checkbox, "RIGHT", 0, 1 )
  enabled_label:SetTextColor( 1, 1, 1, 1 )
  enabled_label:SetText( "Heroic item matching" )

  local inner = m.create_backdrop_frame( api(), "Frame", nil, frame )
  inner:SetBackdrop( control_backdrop )
  inner:SetBackdropColor( 0, 0, 0 )
  inner:SetBackdropBorderColor( 0.4, 0.4, 0.4 )
  inner:SetPoint( "TOPLEFT",     frame, "TOPLEFT",     17,  -60 )
  inner:SetPoint( "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -17,  43 )

  local header_bar = api().CreateFrame( "Frame", nil, inner )
  header_bar:SetPoint( "TOPLEFT",  inner, "TOPLEFT",  4,   -4 )
  header_bar:SetPoint( "TOPRIGHT", inner, "TOPRIGHT", -22, -4 )
  header_bar:SetHeight( HEADER_HEIGHT )

  local header_bg = header_bar:CreateTexture( nil, "BACKGROUND" )
  header_bg:SetAllPoints()
  header_bg:SetTexture( 0.15, 0.15, 0.15, 1 )

  local function make_header_cell( label, x, width )
    local fs = header_bar:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
    fs:SetPoint( "LEFT", header_bar, "LEFT", x + 4, 0 )
    fs:SetWidth( width - 8 )
    fs:SetJustifyH( "LEFT" )
    fs:SetText( m.colors.white( label ) )
  end

  make_header_cell( "Type",          0,                                                                                     MAP_COL_TYPE )
  make_header_cell( "Reserve ID",    MAP_COL_TYPE,                                                                          MAP_COL_RESERVE_ID )
  make_header_cell( "Reserved Item", MAP_COL_TYPE + MAP_COL_RESERVE_ID,                                                     MAP_COL_RESERVE )
  make_header_cell( "Match ID",      MAP_COL_TYPE + MAP_COL_RESERVE_ID + MAP_COL_RESERVE,                                   MAP_COL_MATCH_ID )
  make_header_cell( "Matched Item",  MAP_COL_TYPE + MAP_COL_RESERVE_ID + MAP_COL_RESERVE + MAP_COL_MATCH_ID,                MAP_COL_MATCH )
  make_header_cell( "Rollers",       MAP_COL_TYPE + MAP_COL_RESERVE_ID + MAP_COL_RESERVE + MAP_COL_MATCH_ID + MAP_COL_MATCH, MAP_COL_ROLLERS )

  local scroll_frame = api().CreateFrame( "ScrollFrame", "RollForSRMappingScroll", inner, "UIPanelScrollFrameTemplate" )
  scroll_frame:SetPoint( "TOPLEFT",     header_bar, "BOTTOMLEFT",  0,   -2 )
  scroll_frame:SetPoint( "BOTTOMRIGHT", inner,      "BOTTOMRIGHT", -22,  4 )

  local scroll_child = api().CreateFrame( "Frame", nil, scroll_frame )
  scroll_frame:SetScrollChild( scroll_child )
  scroll_child:SetWidth( 1 )
  scroll_child:SetHeight( 1 )

  local back_button = api().CreateFrame( "Button", nil, frame, "UIPanelButtonTemplate" )
  back_button:SetPoint( "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -27, 17 )
  back_button:SetHeight( 20 )
  back_button:SetWidth( 120 )
  back_button:SetText( "Back to Import" )
  back_button:SetScript( "OnClick", function()
    frame:Hide()
    on_back()
  end )

  local refresh_button = api().CreateFrame( "Button", nil, frame, "UIPanelButtonTemplate" )
  refresh_button:SetPoint( "RIGHT", back_button, "LEFT", -10, 0 )
  refresh_button:SetHeight( 20 )
  refresh_button:SetWidth( 80 )
  refresh_button:SetText( "Refresh" )
  refresh_button:SetScript( "OnClick", function()
    if on_refresh then on_refresh() end
  end )

  local status_label = frame:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
  status_label:SetPoint( "BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 22 )
  status_label:SetTextColor( 0.7, 0.7, 0.7, 1 )

  local row_pool = {}
  local current_rows = {}

  local function acquire_row( index )
    local row = row_pool[ index ]
    if not row then
      row = api().CreateFrame( "Frame", nil, scroll_child )
      row:SetHeight( ROW_HEIGHT )

      local bg = row:CreateTexture( nil, "BACKGROUND" )
      bg:SetAllPoints()
      row.bg = bg

      local function make_cell( x, w )
        local fs = row:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
        fs:SetPoint( "LEFT", row, "LEFT", x + 4, 0 )
        fs:SetWidth( w - 8 )
        fs:SetJustifyH( "LEFT" )
        return fs
      end

      local function make_item_cell( x, w )
        local button = api().CreateFrame( "Button", nil, row )
        button:SetPoint( "LEFT", row, "LEFT", x + 4, 0 )
        button:SetWidth( w - 8 )
        button:SetHeight( ROW_HEIGHT )
        button:EnableMouse( true )

        local fs = button:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
        fs:SetPoint( "LEFT", button, "LEFT", 0, 0 )
        fs:SetWidth( w - 8 )
        fs:SetJustifyH( "LEFT" )
        button.text = fs

        button:SetScript( "OnEnter", function( self )
          if not self.item_id then return end
          api().GameTooltip:SetOwner( self, "ANCHOR_RIGHT" )
          api().GameTooltip:SetHyperlink( string.format( "item:%s:0:0:0:0:0:0:0", self.item_id ) )
          api().GameTooltip:Show()
        end )
        button:SetScript( "OnLeave", function() api().GameTooltip:Hide() end )

        return button
      end

      row.cell_type       = make_cell( 0,                                                                                     MAP_COL_TYPE )
      row.cell_reserve_id = make_cell( MAP_COL_TYPE,                                                                          MAP_COL_RESERVE_ID )
      row.cell_reserve    = make_item_cell( MAP_COL_TYPE + MAP_COL_RESERVE_ID,                                                MAP_COL_RESERVE )
      row.cell_match_id   = make_cell( MAP_COL_TYPE + MAP_COL_RESERVE_ID + MAP_COL_RESERVE,                                   MAP_COL_MATCH_ID )
      row.cell_match      = make_item_cell( MAP_COL_TYPE + MAP_COL_RESERVE_ID + MAP_COL_RESERVE + MAP_COL_MATCH_ID,           MAP_COL_MATCH )
      row.cell_rollers    = make_cell( MAP_COL_TYPE + MAP_COL_RESERVE_ID + MAP_COL_RESERVE + MAP_COL_MATCH_ID + MAP_COL_MATCH, MAP_COL_ROLLERS )

      row_pool[ index ] = row
    end
    return row
  end

  local function set_item_cell( cell, item_id, quality, item_name, empty_text )
    cell.item_id = item_id
    cell:EnableMouse( item_id ~= nil )

    if not item_id then
      cell.text:SetText( m.colors.grey( empty_text or "-" ) )
      return
    end

    local item_text = m.fetch_item_link( item_id, quality ) or item_name or m.colors.grey( "waiting for item cache" )
    cell.text:SetText( item_text )
  end

  local function render_rows()
    local total_width = scroll_frame:GetWidth()

    for i, data in ipairs( current_rows ) do
      local row = acquire_row( i )
      row:ClearAllPoints()
      row:SetPoint( "TOPLEFT", scroll_child, "TOPLEFT", 0, -( (i - 1) * ROW_HEIGHT ) )
      row:SetWidth( total_width )
      row:Show()
      row:EnableMouse( false )

      if i % 2 == 0 then
        row.bg:SetTexture( 0.10, 0.10, 0.10, 0.8 )
      else
        row.bg:SetTexture( 0.06, 0.06, 0.06, 0.8 )
      end

      row.cell_type:SetText( data.type == "HR" and m.colors.red( "HR" ) or m.colors.blue( "SR" ) )
      row.cell_reserve_id:SetText( tostring( data.reserve_item_id ) )
      set_item_cell( row.cell_reserve, data.reserve_item_id, data.reserve_quality, data.reserve_item_name )
      row.cell_match_id:SetText( data.matched_item_id and tostring( data.matched_item_id ) or m.colors.grey( "-" ) )
      set_item_cell( row.cell_match, data.matched_item_id, nil, data.matched_item_name, "not resolved yet" )
      row.cell_rollers:SetText( data.rollers and tostring( data.rollers ) or m.colors.grey( "-" ) )
    end

    for i = #current_rows + 1, #row_pool do
      if row_pool[ i ] then row_pool[ i ]:Hide() end
    end

    scroll_child:SetHeight( math.max( 1, #current_rows * ROW_HEIGHT ) )
    scroll_child:SetWidth( math.max( 1, total_width ) )
    scroll_frame:UpdateScrollChildRect()
    scroll_frame:SetVerticalScroll( 0 )
  end

  frame.populate = function( info )
    current_rows = info and info.rows or {}
    enabled_checkbox:SetChecked( info and info.enabled or false )

    if #current_rows == 0 then
      status_label:SetText( "No soft-reserve items imported." )
    elseif info and info.all_resolved then
      status_label:SetText( "Ready. Matched Item uses original 3.3.5 ToGC heroic IDs resolved by this client." )
    else
      status_label:SetText( "Some item names are still waiting for the 3.3.5a client cache. Wait a moment, then Refresh." )
    end

    render_rows()
  end

  ---@diagnostic disable-next-line: undefined-global
  table.insert( UISpecialFrames, "RollForSoftResMappingFrame" )
  return frame
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

function M.new( api, import_encoded_softres_data, softres_check, softres, clear_data, reset_loot_announcements, ace_timer, group_roster, unfiltered_softres, use_item_names, refresh_softres_data )
  local softres_data_encoded
  local edit_box_text
  local dirty        = false
  local import_frame
  local table_frame
  local mapping_frame
  local fetch_retries = 0

  -- Build the flat sorted row list from current softres/hardres data.
  -- Returns rows, needs_refetch.
  local function build_rows()
    local hr_rows      = {}
    local sr_rows      = {}
    local needs_refetch = false

    local function touch( item_id )
      m.set_game_tooltip_with_item_id( item_id )
      needs_refetch = true
    end

    -- HR rows
    for _, item_id in ipairs( unfiltered_softres.get_hr_item_ids() ) do
      local quality   = unfiltered_softres.get_item_quality( item_id )
      local item_link = m.fetch_item_link( item_id, quality )

      if not item_link and fetch_retries < MAX_RETRIES then touch( item_id ) end

      table.insert( hr_rows, {
        item_id  = item_id,
        item_link = item_link,
      } )
    end

    -- SR rows: flatten all rollers across all items, then sort by player name
    local sr_pairs = {}

    for _, item_id in ipairs( unfiltered_softres.get_item_ids() ) do
      local rollers = unfiltered_softres.get( item_id )
      for _, roller in ipairs( rollers ) do
        table.insert( sr_pairs, {
          name    = roller.name,
          item_id = item_id,
          sr_plus = roller.sr_plus,
          quality = unfiltered_softres.get_item_quality( item_id ),
        } )
      end
    end

    table.sort( sr_pairs, function( a, b )
      if a.name ~= b.name then return a.name < b.name end
      return a.item_id < b.item_id
    end )

    for _, pair in ipairs( sr_pairs ) do
      local item_link = m.fetch_item_link( pair.item_id, pair.quality )
      if not item_link and fetch_retries < MAX_RETRIES then touch( pair.item_id ) end

      local player_text = pair.name
      if group_roster then
        local player = group_roster.find_player( pair.name )
        if player and player.class then
          player_text = m.colorize_player_by_class( pair.name, player.class )
        end
      end

      table.insert( sr_rows, {
        player_text = player_text,
        item_id     = pair.item_id,
        item_link   = item_link,
        sr_plus     = pair.sr_plus,
      } )
    end

    return hr_rows, sr_rows, needs_refetch
  end

  local function show_table( is_retry )
    if not is_retry then fetch_retries = 0 end

    if not table_frame then
      table_frame = create_table_frame( api, function()
        -- "Back to Import" pressed
        import_frame:Show()
        import_frame.editbox:SetText( softres_data_encoded or "" )
      end )
    end

    local hr_rows, sr_rows, needs_refetch = build_rows()
    table_frame.populate( hr_rows, sr_rows )

    if needs_refetch then
      fetch_retries = fetch_retries + 1
      table_frame.status_label:SetText(
        string.format( "Fetching item details… (attempt %d/%d)", fetch_retries, MAX_RETRIES ) )
      ace_timer.ScheduleTimer( M, function() show_table( true ) end, RETRY_INTERVAL )
    else
      table_frame.status_label:SetText( "" )
    end

    table_frame:Show()
  end

  -- ---------------------------------------------------------------------------
  -- Import frame callbacks
  -- ---------------------------------------------------------------------------

  local function on_import( close_window_fn )
    import_encoded_softres_data( edit_box_text, function()
      local result = softres_check.check_softres()

      if result ~= softres_check.ResultType.NoItemsFound then
        softres_data_encoded = edit_box_text
        softres.persist( softres_data_encoded )
        close_window_fn()
        reset_loot_announcements()
      end
    end )
  end

  local function on_clear()
    edit_box_text        = nil
    softres_data_encoded = nil
    dirty                = false

    if import_frame then
      import_frame.editbox:SetText( "" )
      import_frame.editbox:SetFocus()
    end

    clear_data()
    reset_loot_announcements()
  end

  local function on_cancel()
    edit_box_text = softres_data_encoded
    dirty         = false
    return softres_data_encoded
  end

  local function on_use_item_names_toggled( checked )
    if not use_item_names then return end
    use_item_names.set_enabled( checked )
    if refresh_softres_data then refresh_softres_data() end
  end

  local function on_dirty( import_button, clear_button, cancel_button )
    local text = import_frame.editbox:GetText()
    if text == "" then text = nil end

    if edit_box_text ~= text then
      dirty         = true
      edit_box_text = text
    end

    cancel_button:SetText( dirty and "Cancel" or "Close" )

    if dirty then
      if edit_box_text == softres_data_encoded then
        import_button:Disable()
      else
        import_button:Enable()
      end
      clear_button:Enable()
      return
    end

    import_button:Disable()
    if text == nil then
      clear_button:Disable()
    else
      clear_button:Enable()
    end
  end

  -- ---------------------------------------------------------------------------
  -- Public API
  -- ---------------------------------------------------------------------------

  local show_mapping

  local function ensure_import_frame()
    if import_frame then return end
    import_frame = create_import_frame( api, on_import, on_clear, on_cancel, on_dirty,
      use_item_names, on_use_item_names_toggled, function() show_mapping() end )
  end

  show_mapping = function()
    ensure_import_frame()

    if not mapping_frame then
      mapping_frame = create_mapping_frame( api, function()
        import_frame:Show()
        import_frame.editbox:SetText( softres_data_encoded or "" )
      end, use_item_names, on_use_item_names_toggled, function() show_mapping() end )
    end

    if table_frame then table_frame:Hide() end
    import_frame:Hide()
    mapping_frame.populate( unfiltered_softres.get_name_mapping_info() )
    mapping_frame:Show()
  end

  local function toggle()
    ensure_import_frame()

    if mapping_frame and mapping_frame:IsVisible() then
      mapping_frame:Hide()
      return
    end

    if table_frame and table_frame:IsVisible() then
      table_frame:Hide()
      return
    end

    if import_frame:IsVisible() then
      import_frame:Hide()
      return
    end

    -- Nothing open — show table if data exists, otherwise show import editbox
    if softres_data_encoded and softres_data_encoded ~= "" then
      show_table( false )
    else
      dirty = false
      import_frame.editbox:SetText( "" )
      import_frame:Show()
      import_frame.editbox:SetFocus()
    end
  end

  local function load( data )
    softres_data_encoded = data
  end

  local function clear()
    edit_box_text        = nil
    softres_data_encoded = nil
    dirty                = false

    if import_frame then import_frame.editbox:SetText( "" ) end

    reset_loot_announcements()
  end

  return {
    toggle       = toggle,
    show_mapping = show_mapping,
    load         = load,
    clear        = clear,
  }
end

m.SoftResGui = M
return M
