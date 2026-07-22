RollFor = RollFor or {}
local m = RollFor

if m.RaidRecap then return end

local M = {}
local getn = m.getn

---@diagnostic disable-next-line: undefined-global
local UIParent = UIParent
---@diagnostic disable-next-line: undefined-global
local date = date
---@diagnostic disable-next-line: undefined-global
local time = time

local frame_backdrop = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true,
  tileSize = 32,
  edgeSize = 32,
  insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

local control_backdrop = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true,
  tileSize = 16,
  edgeSize = 16,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

local FRAME_WIDTH = 840
local FRAME_HEIGHT = 460
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 22

local COL_TIME = 88
local COL_INSTANCE = 180
local COL_ITEM = 285
local COL_WINNER = 130
local COL_ROLL = 55
local COL_TYPE = 60

local function now()
  local time_fn = m.lua and m.lua.time or time
  return time_fn and time_fn() or 0
end

local function safe_call( f )
  if type( f ) ~= "function" then return end
  local ok, a, b, c, d, e = pcall( f )
  if ok then return a, b, c, d, e end
end

local function non_empty( value )
  if value and value ~= "" then return value end
end

local function instance_key( context )
  if not context then return "" end
  return string.format( "%s:%s:%s:%s",
    context.name or "",
    context.instance_type or "",
    context.difficulty_index or "",
    context.max_players or "" )
end

local function strategy_text( strategy )
  local RS = m.Types.RollingStrategy

  if strategy == RS.SoftResRoll then
    return "SR"
  elseif strategy == RS.NormalRoll then
    return "Open"
  elseif strategy == RS.TieRoll then
    return "Tie"
  elseif strategy == RS.RaidRoll then
    return "RR"
  elseif strategy == RS.InstaRaidRoll then
    return "IRR"
  end

  return tostring( strategy or "-" )
end

local function roll_type_text( roll_type, strategy )
  if roll_type then
    local ok, text = pcall( m.roll_type_abbrev, roll_type )
    if ok and text then return text end
  end

  return strategy_text( strategy )
end

local function player_text( name, class )
  if not name or name == "" then return m.colors.grey( "-" ) end
  if class then return m.colorize_player_by_class( name, class ) end
  return name
end

local function item_tooltip_link( item_id, item_link )
  if item_link then
    local link = m.ItemUtils.get_tooltip_link( item_link )
    if link then return link end
  end

  if item_id then
    return string.format( "item:%s:0:0:0:0:0:0:0", item_id )
  end
end

local function item_display_text( item_id, item_link, item_name )
  if not item_id and not item_link and not item_name then return m.colors.grey( "-" ) end

  local id_text = item_id and string.format( "%s ", m.colors.grey( tostring( item_id ) ) ) or ""
  return id_text .. (item_link or item_name or m.colors.grey( "waiting for item cache" ))
end

function M.new( db, api, roll_controller, confirm_popup )
  db.entries = db.entries or {}

  local frame
  local scroll_frame
  local scroll_child
  local status_label
  local row_pool = {}

  local function wow()
    return type( api ) == "function" and api() or api or m.api
  end

  local function detect_instance()
    local a = wow()
    local name, instance_type, difficulty_index, difficulty_name, max_players

    if a and a.GetInstanceInfo then
      name, instance_type, difficulty_index, difficulty_name, max_players = safe_call( a.GetInstanceInfo )
    end

    local real_zone = a and safe_call( a.GetRealZoneText )
    local zone = real_zone or (a and safe_call( a.GetZoneText ))

    return {
      name = non_empty( name ) or non_empty( zone ) or "Unknown",
      zone_name = zone,
      instance_type = instance_type,
      difficulty_index = difficulty_index,
      difficulty_name = difficulty_name,
      max_players = max_players
    }
  end

  local function set_current_instance( context )
    local previous = db.current_instance
    context.entered_at = previous and instance_key( previous ) == instance_key( context ) and previous.entered_at or now()
    db.current_instance = context
    return context
  end

  local function current_instance()
    return set_current_instance( detect_instance() )
  end

  local function format_time( timestamp )
    local a = wow()
    local date_fn = a and a.date or date

    if timestamp and date_fn then
      local ok, text = pcall( date_fn, "%m/%d %H:%M", timestamp )
      if ok and text then return text end
    end

    return m.colors.grey( "-" )
  end

  local function format_instance( entry )
    local text = entry.instance_name or entry.zone_name or "Unknown"
    local difficulty = entry.difficulty_name

    if difficulty and difficulty ~= "" and not string.find( text, difficulty, 1, true ) then
      text = string.format( "%s %s", text, difficulty )
    end

    return text
  end

  local function set_cell_text( cell, text )
    cell:SetText( text or "" )
  end

  local function set_item_cell( cell, entry )
    cell.item_id = entry.item_id
    cell.item_link = entry.item_link
    cell.tooltip_link = item_tooltip_link( entry.item_id, entry.item_link )
    cell:EnableMouse( cell.tooltip_link ~= nil )
    cell.text:SetText( item_display_text( entry.item_id, entry.item_link, entry.item_name ) )
  end

  local function clear_history()
    m.clear_table( db.entries )
    if m.vanilla then db.entries.n = 0 end

    if frame and frame:IsVisible() then
      frame.render()
    end
  end

  local function confirm_clear()
    if confirm_popup and confirm_popup.is_visible and confirm_popup.is_visible() then
      confirm_popup.hide()
      return
    end

    if confirm_popup and confirm_popup.show then
      confirm_popup.show( { "This will clear raid recap history.", "Are you sure?" }, function( value )
        if value then clear_history() end
      end )
      return
    end

    clear_history()
  end

  local function create_header_cell( parent, label, x, width )
    local cell = parent:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
    cell:SetPoint( "LEFT", parent, "LEFT", x + 4, 0 )
    cell:SetWidth( width - 8 )
    cell:SetJustifyH( "LEFT" )
    cell:SetText( m.colors.white( label ) )
    return cell
  end

  local function create_text_cell( row, x, width )
    local cell = row:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
    cell:SetPoint( "LEFT", row, "LEFT", x + 4, 0 )
    cell:SetWidth( width - 8 )
    cell:SetJustifyH( "LEFT" )
    return cell
  end

  local function create_item_cell( row, x, width )
    local button = wow().CreateFrame( "Button", nil, row )
    button:SetPoint( "LEFT", row, "LEFT", x + 4, 0 )
    button:SetWidth( width - 8 )
    button:SetHeight( ROW_HEIGHT )
    button:EnableMouse( true )

    local text = button:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
    text:SetPoint( "LEFT", button, "LEFT", 0, 0 )
    text:SetWidth( width - 8 )
    text:SetJustifyH( "LEFT" )
    button.text = text

    button:SetScript( "OnEnter", function( self )
      if not self.tooltip_link then return end
      wow().GameTooltip:SetOwner( self, "ANCHOR_RIGHT" )
      wow().GameTooltip:SetHyperlink( self.tooltip_link )
      wow().GameTooltip:Show()
    end )
    button:SetScript( "OnLeave", function() wow().GameTooltip:Hide() end )
    button:SetScript( "OnClick", function( self )
      if not self.tooltip_link then return end

      if m.is_ctrl_key_down() and self.item_link and wow().DressUpItemLink then
        wow().DressUpItemLink( self.item_link )
      elseif m.is_shift_key_down() and self.item_link then
        m.link_item_in_chat( self.item_link )
      elseif wow().SetItemRef then
        wow().SetItemRef( self.tooltip_link, self.tooltip_link, "LeftButton" )
      end
    end )

    return button
  end

  local function acquire_row( index )
    local row = row_pool[ index ]

    if not row then
      row = wow().CreateFrame( "Frame", nil, scroll_child )
      row:SetHeight( ROW_HEIGHT )

      local bg = row:CreateTexture( nil, "BACKGROUND" )
      bg:SetAllPoints()
      row.bg = bg

      row.cell_time = create_text_cell( row, 0, COL_TIME )
      row.cell_instance = create_text_cell( row, COL_TIME, COL_INSTANCE )
      row.cell_item = create_item_cell( row, COL_TIME + COL_INSTANCE, COL_ITEM )
      row.cell_winner = create_text_cell( row, COL_TIME + COL_INSTANCE + COL_ITEM, COL_WINNER )
      row.cell_roll = create_text_cell( row, COL_TIME + COL_INSTANCE + COL_ITEM + COL_WINNER, COL_ROLL )
      row.cell_type = create_text_cell( row, COL_TIME + COL_INSTANCE + COL_ITEM + COL_WINNER + COL_ROLL, COL_TYPE )

      row_pool[ index ] = row
    end

    return row
  end

  local function render_rows()
    local entries = db.entries or {}
    local count = getn( entries )
    local total_width = scroll_frame:GetWidth()

    for i = 1, count do
      local entry = entries[ count - i + 1 ]
      local row = acquire_row( i )
      row:ClearAllPoints()
      row:SetPoint( "TOPLEFT", scroll_child, "TOPLEFT", 0, -( (i - 1) * ROW_HEIGHT ) )
      row:SetWidth( total_width )
      row:Show()

      if i % 2 == 0 then
        row.bg:SetTexture( 0.10, 0.10, 0.10, 0.8 )
      else
        row.bg:SetTexture( 0.06, 0.06, 0.06, 0.8 )
      end

      set_cell_text( row.cell_time, format_time( entry.timestamp ) )
      set_cell_text( row.cell_instance, format_instance( entry ) )
      set_item_cell( row.cell_item, entry )
      set_cell_text( row.cell_winner, player_text( entry.winner_name, entry.winner_class ) )
      set_cell_text( row.cell_roll, entry.winning_roll and tostring( entry.winning_roll ) or m.colors.grey( "-" ) )
      set_cell_text( row.cell_type, roll_type_text( entry.roll_type, entry.rolling_strategy ) )
    end

    for i = count + 1, getn( row_pool ) do
      if row_pool[ i ] then row_pool[ i ]:Hide() end
    end

    scroll_child:SetHeight( math.max( 1, count * ROW_HEIGHT ) )
    scroll_child:SetWidth( math.max( 1, total_width ) )
    scroll_frame:UpdateScrollChildRect()

    if count == 0 then
      status_label:SetText( "No raid recap history yet." )
    else
      status_label:SetText( string.format( "%d recap entr%s. Newest entries are shown first.",
        count,
        count == 1 and "y" or "ies" ) )
    end
  end

  local function create_frame()
    local a = wow()
    local parent = a.UIParent or UIParent
    local f = m.create_backdrop_frame( a, "Frame", "RollForRaidRecapFrame", parent )
    f:Hide()
    f:SetWidth( FRAME_WIDTH )
    f:SetHeight( FRAME_HEIGHT )
    f:SetPoint( "CENTER", parent, "CENTER", 0, 0 )
    f:EnableMouse()
    f:SetMovable( true )
    f:RegisterForDrag( "LeftButton" )
    f:SetScript( "OnDragStart", function( self ) self:StartMoving() end )
    f:SetScript( "OnDragStop", function( self ) self:StopMovingOrSizing() end )
    f:SetFrameStrata( "DIALOG" )
    f:SetBackdrop( frame_backdrop )
    f:SetBackdropColor( 0, 0, 0, 1 )
    f:SetToplevel( true )

    local close_button = a.CreateFrame( "Button", nil, f, "UIPanelCloseButton" )
    close_button:SetPoint( "TOPRIGHT", f, "TOPRIGHT", 0, 0 )
    close_button:SetScript( "OnClick", function() f:Hide() end )

    local title = f:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
    title:SetPoint( "TOPLEFT", f, "TOPLEFT", 20, -14 )
    title:SetTextColor( 1, 1, 1, 1 )
    title:SetText( string.format( "%s  -  Raid Recap", m.colors.blue( "rollfor_cool" ) ) )

    local inner = m.create_backdrop_frame( a, "Frame", nil, f )
    inner:SetBackdrop( control_backdrop )
    inner:SetBackdropColor( 0, 0, 0 )
    inner:SetBackdropBorderColor( 0.4, 0.4, 0.4 )
    inner:SetPoint( "TOPLEFT", f, "TOPLEFT", 17, -35 )
    inner:SetPoint( "BOTTOMRIGHT", f, "BOTTOMRIGHT", -17, 43 )

    local header_bar = a.CreateFrame( "Frame", nil, inner )
    header_bar:SetPoint( "TOPLEFT", inner, "TOPLEFT", 4, -4 )
    header_bar:SetPoint( "TOPRIGHT", inner, "TOPRIGHT", -22, -4 )
    header_bar:SetHeight( HEADER_HEIGHT )

    local header_bg = header_bar:CreateTexture( nil, "BACKGROUND" )
    header_bg:SetAllPoints()
    header_bg:SetTexture( 0.15, 0.15, 0.15, 1 )

    create_header_cell( header_bar, "Time", 0, COL_TIME )
    create_header_cell( header_bar, "Instance", COL_TIME, COL_INSTANCE )
    create_header_cell( header_bar, "Item", COL_TIME + COL_INSTANCE, COL_ITEM )
    create_header_cell( header_bar, "Winner", COL_TIME + COL_INSTANCE + COL_ITEM, COL_WINNER )
    create_header_cell( header_bar, "Roll", COL_TIME + COL_INSTANCE + COL_ITEM + COL_WINNER, COL_ROLL )
    create_header_cell( header_bar, "Type", COL_TIME + COL_INSTANCE + COL_ITEM + COL_WINNER + COL_ROLL, COL_TYPE )

    scroll_frame = a.CreateFrame( "ScrollFrame", "RollForRaidRecapScroll", inner, "UIPanelScrollFrameTemplate" )
    scroll_frame:SetPoint( "TOPLEFT", header_bar, "BOTTOMLEFT", 0, -2 )
    scroll_frame:SetPoint( "BOTTOMRIGHT", inner, "BOTTOMRIGHT", -22, 4 )

    scroll_child = a.CreateFrame( "Frame", nil, scroll_frame )
    scroll_frame:SetScrollChild( scroll_child )
    scroll_child:SetWidth( 1 )
    scroll_child:SetHeight( 1 )

    local clear_button = a.CreateFrame( "Button", nil, f, "UIPanelButtonTemplate" )
    clear_button:SetPoint( "BOTTOMRIGHT", f, "BOTTOMRIGHT", -27, 17 )
    clear_button:SetHeight( 20 )
    clear_button:SetWidth( 115 )
    clear_button:SetText( "Clear History" )
    clear_button:SetScript( "OnClick", confirm_clear )

    status_label = f:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
    status_label:SetPoint( "BOTTOMLEFT", f, "BOTTOMLEFT", 20, 22 )
    status_label:SetTextColor( 0.7, 0.7, 0.7, 1 )

    f.render = render_rows
    f:SetScript( "OnShow", function() f.render() end )

    ---@diagnostic disable-next-line: undefined-global
    table.insert( UISpecialFrames, "RollForRaidRecapFrame" )
    return f
  end

  local function record_winners( data )
    if not data or not data.item or not data.winners then return end

    local context = current_instance()

    for _, winner in ipairs( data.winners ) do
      if type( winner ) == "table" then
        table.insert( db.entries, {
          timestamp = now(),
          instance_entered_at = context.entered_at,
          instance_name = context.name,
          zone_name = context.zone_name,
          instance_type = context.instance_type,
          difficulty_index = context.difficulty_index,
          difficulty_name = context.difficulty_name,
          max_players = context.max_players,
          item_id = data.item.id,
          item_name = data.item.name,
          item_link = data.item.link,
          item_count = data.item_count,
          winner_name = winner.name,
          winner_class = winner.class,
          winning_roll = winner.winning_roll,
          roll_type = winner.roll_type,
          rolling_strategy = data.rolling_strategy
        } )
      end
    end

    if frame and frame:IsVisible() then frame.render() end
  end

  local function show()
    if not frame then frame = create_frame() end
    current_instance()
    frame:Show()
    frame.render()
  end

  local function hide()
    if frame then frame:Hide() end
  end

  local function toggle()
    if frame and frame:IsVisible() then
      hide()
    else
      show()
    end
  end

  if roll_controller and roll_controller.subscribe then
    roll_controller.subscribe( "winners_found", record_winners )
  end

  return {
    show = show,
    hide = hide,
    toggle = toggle,
    clear = clear_history,
    confirm_clear = confirm_clear,
    on_zone_changed = function() current_instance() end
  }
end

m.RaidRecap = M
return M
