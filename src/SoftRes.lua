RollFor = RollFor or {}
local m = RollFor

if m.SoftRes then return end

local M = {}

---@diagnostic disable-next-line: undefined-global
local lib_stub = LibStub

local keys = m.keys
local transform = m.SoftResDataTransformer.transform

-- Original Wrath 3.3.5 Trial of the Grand Crusader heroic item ID bands.
-- The client is still asked for each item's name before a match is trusted.
local TOGC_HEROIC_ITEM_ID_RANGES = {
  { 47412, 47561 }, -- 25-player heroic / tribute items
  { 47913, 48030 }  -- 10-player heroic / tribute items
}

---@class UseItemNames
---@field is_enabled fun(): boolean
---@field set_enabled fun( value: boolean )

---@param existing SoftRessedItem
---@param incoming SoftRessedItem
---@return SoftRessedItem
local function merge_softressed_items( existing, incoming )
  local rollers = {}
  local seen = {}

  for _, roller in ipairs( existing.rollers or {} ) do
    if not seen[ roller.name ] then
      table.insert( rollers, roller )
      seen[ roller.name ] = true
    end
  end

  for _, roller in ipairs( incoming.rollers or {} ) do
    if not seen[ roller.name ] then
      table.insert( rollers, roller )
      seen[ roller.name ] = true
    end
  end

  return {
    quality = existing.quality or incoming.quality,
    name = existing.name or incoming.name,
    rollers = rollers
  }
end

---@param existing HardRessedItem
---@param incoming HardRessedItem
---@return HardRessedItem
local function merge_hardressed_items( existing, incoming )
  return {
    quality = existing.quality or incoming.quality,
    name = existing.name or incoming.name
  }
end

local RETRY_INTERVAL = 15

---@param db table
---@param use_item_names UseItemNames?
---@param ace_timer AceTimer?
function M.new( db, use_item_names, ace_timer )
  ---@type SoftResData
  local softres_data = {}
  local hardres_data = {}

  -- Name-based matching: a soft-reserved item id (as referenced by softres.it) is matched to
  -- whatever item id actually drops by comparing display names. This avoids baking in WotLK
  -- Classic/re-release ids; on 3.3.5a/Warmane the running client and imported export names are
  -- the source of truth. See `get_effective_entry`.
  local sr_name_index, hr_name_index = {}, {}   -- normalized_name -> { item_id, ... }
  local name_index_dirty = true
  -- dropped_item_id -> effective entry, or false if checked with no match. Kept separate per data
  -- table (soft-res vs hard-res), since a miss against one doesn't imply a miss against the other.
  local sr_pending_lookup_ids, hr_pending_lookup_ids = {}, {}
  local sr_name_match_history, hr_name_match_history = {}, {}
  local retry_scheduled = false

  local function clear_lookup_cache( cache )
    for k in pairs( cache ) do
      cache[ k ] = nil
    end
  end

  local function copy_item_ids( item_ids )
    local result = {}
    for _, id in ipairs( item_ids or {} ) do
      table.insert( result, id )
    end
    return result
  end

  local function record_name_match( dropped_item_id, dropped_item_name, matched_item_ids, history )
    if not history then return end
    history[ dropped_item_id ] = {
      item_id = dropped_item_id,
      name = dropped_item_name,
      matched_item_ids = copy_item_ids( matched_item_ids )
    }
  end

  local function normalize_name( name )
    if type( name ) ~= "string" or name == "" then return nil end
    name = string.gsub( name, "^%s+", "" )
    name = string.gsub( name, "%s+$", "" )
    name = string.gsub( name, "%s*%([Hh]eroic%)%s*$", "" )
    return string.lower( name )
  end

  local function warm_item_cache( item_id )
    if m.api.GameTooltip and m.set_game_tooltip_with_item_id then
      m.set_game_tooltip_with_item_id( item_id )
    end
  end

  local function get_item_name( item_id, item )
    local name = item and item.name or nil
    if name then return name end

    name = m.api.GetItemInfo( item_id )
    if not name then warm_item_cache( item_id ) end
    return name
  end

  local function index_table( data, name_index )
    local all_resolved = true

    for item_id, item in pairs( data ) do
      local name = get_item_name( item_id, item )

      if name then
        local key = normalize_name( name )
        if key then
          name_index[ key ] = name_index[ key ] or {}
          table.insert( name_index[ key ], item_id )
        end
      else
        all_resolved = false
      end
    end

    return all_resolved
  end

  local function build_name_index()
    clear_lookup_cache( sr_name_index )
    clear_lookup_cache( hr_name_index )
    clear_lookup_cache( sr_pending_lookup_ids )
    clear_lookup_cache( hr_pending_lookup_ids )

    local sr_resolved = index_table( softres_data, sr_name_index )
    local hr_resolved = index_table( hardres_data, hr_name_index )

    name_index_dirty = not (sr_resolved and hr_resolved)

    if name_index_dirty and ace_timer and not retry_scheduled then
      retry_scheduled = true
      ace_timer.ScheduleTimer( M, function()
        retry_scheduled = false
        build_name_index()
      end, RETRY_INTERVAL )
    end
  end

  -- Resolves the effective SR/HR entry for a dropped `item_id`: a direct id match (fast path),
  -- else -- when enabled -- a name-based match against `data`'s own keys. When more than one of
  -- `data`'s keys share the dropped item's name, their entries are combined via `merge_fn`.
  ---@param item_id number
  ---@param data table<number, table>
  ---@param name_index table<string, number[]>
  ---@param lookup_cache table<number, table|false>
  ---@param merge_fn fun( existing: table, incoming: table ): table
  ---@param match_history table<number, table>?
  local function get_effective_entry( item_id, data, name_index, lookup_cache, merge_fn, match_history )
    if data[ item_id ] then return data[ item_id ] end

    if not use_item_names or not use_item_names.is_enabled() then return nil end

    if name_index_dirty then build_name_index() end

    if lookup_cache[ item_id ] == false then return nil end
    if lookup_cache[ item_id ] then return lookup_cache[ item_id ] end

    local name = m.api.GetItemInfo( item_id )
    if not name then
      warm_item_cache( item_id )
      return nil
    end

    local matches = name_index[ normalize_name( name ) ]
    if not matches or not matches[ 1 ] then
      lookup_cache[ item_id ] = false
      return nil
    end

    record_name_match( item_id, name, matches, match_history )

    local merged = data[ matches[ 1 ] ]
    for i = 2, #matches do
      merged = merge_fn( merged, data[ matches[ i ] ] )
    end

    lookup_cache[ item_id ] = merged
    return merged
  end

  local function persist( data )
    if data ~= nil then
      db.import_timestamp = m.lua.time()
    else
      db.import_timestamp = nil
    end

    db.data = data
  end

  function M.decode( encoded_softres_data )
    if not encoded_softres_data then return nil end

    local data = m.decode_base64( encoded_softres_data )

    if not data then
      m.pretty_print( "Couldn't decode softres data!", m.colors.red )
      return nil
    end

    if m.bcc or m.wotlk then
      -- Try zlib decompression first (softres.it exports are compressed).
      -- If it fails, fall through and treat data as plain JSON (e.g. custom export tools).
      local decompressed = LibStub( "LibDeflate" ):DecompressZlib( data )
      if decompressed then
        data = decompressed
      end
      -- If decompressed is nil, data is left as-is and JSON parsing below will validate it.
    end

    local json = lib_stub( "Json-0.1.2" )
    local success, result = pcall( function() return json.decode( data ) end )
    return success and result
  end

  local function reset_name_index()
    sr_name_index, hr_name_index = {}, {}
    sr_pending_lookup_ids, hr_pending_lookup_ids = {}, {}
    sr_name_match_history, hr_name_match_history = {}, {}
    name_index_dirty = true
  end

  local function clear( report )
    if m.count_elements( softres_data ) == 0 and m.count_elements( hardres_data ) == 0 then return end
    softres_data = {}
    hardres_data = {}
    reset_name_index()
    persist( nil )
    if report then m.pretty_print( "Cleared soft-res data." ) end
  end

  local function get( item_id )
    local entry = get_effective_entry( item_id, softres_data, sr_name_index, sr_pending_lookup_ids, merge_softressed_items, sr_name_match_history )
    return entry and m.clone( entry.rollers ) or {}
  end

  local function get_all_rollers()
    local roller_name_map = {}

    for _, item in pairs( softres_data ) do
      for _, roller in pairs( item.rollers or {} ) do
        roller_name_map[ roller.name ] = roller
      end
    end

    local result = {}

    for _, roller in pairs( roller_name_map ) do
      table.insert( result, roller )
    end

    return result
  end

  local function find_roller( player_name, data )
    for _, player in ipairs( data ) do
      if player.name == player_name then return player end
    end
  end

  local function is_player_softressing( player_name, item_id )
    if item_id then
      local entry = get_effective_entry( item_id, softres_data, sr_name_index, sr_pending_lookup_ids, merge_softressed_items, sr_name_match_history )
      local player = entry and find_roller( player_name, entry.rollers )
      return player ~= nil and player.name == player_name
    end

    for _, item in pairs( softres_data ) do
      local roller = find_roller( player_name, item.rollers )
      if roller and roller.name == player_name then return true end
    end

    return false
  end

  local function sort_players()
    for _, item in pairs( softres_data ) do
      if item.rollers then
        table.sort( item.rollers, function( left, right ) return left.name < right.name end )
      end
    end
  end

  local function import( data )
    clear()
    if not data then return end

    softres_data, hardres_data = transform( data )
    reset_name_index()

    sort_players()
    if use_item_names and use_item_names.is_enabled() then build_name_index() end
  end

  local function get_item_ids()
    local result = {}

    for k, _ in pairs( softres_data ) do
      table.insert( result, k )
    end

    return result
  end

  local function get_hr_item_ids()
    return keys( hardres_data )
  end

  local function is_item_hardressed( item_id )
    return get_effective_entry( item_id, hardres_data, hr_name_index, hr_pending_lookup_ids, merge_hardressed_items, hr_name_match_history ) ~= nil
  end

  local function get_item_quality( item_id )
    local sr_entry = get_effective_entry( item_id, softres_data, sr_name_index, sr_pending_lookup_ids, merge_softressed_items, sr_name_match_history )
    if sr_entry then return sr_entry.quality end

    local hr_entry = get_effective_entry( item_id, hardres_data, hr_name_index, hr_pending_lookup_ids, merge_hardressed_items, hr_name_match_history )
    return hr_entry and hr_entry.quality
  end

  local function get_player_items( player_name )
    local result = {}

    for item_id, item in pairs( softres_data ) do
      for _, roller in ipairs( item.rollers or {} ) do
        if roller.name == player_name then
          table.insert( result, {
            item_id = item_id,
            quality = item.quality,
          } )
          break
        end
      end
    end

    return result
  end

  local function get_history_by_source_item_id( history )
    local result = {}

    for dropped_item_id, match in pairs( history ) do
      for _, source_item_id in ipairs( match.matched_item_ids or {} ) do
        result[ source_item_id ] = result[ source_item_id ] or {}
        table.insert( result[ source_item_id ], {
          item_id = dropped_item_id,
          item_name = match.name
        } )
      end
    end

    for _, matches in pairs( result ) do
      table.sort( matches, function( left, right ) return left.item_id < right.item_id end )
    end

    return result
  end

  local function add_match( result, source_item_id, matched_item )
    result[ source_item_id ] = result[ source_item_id ] or {}

    for _, existing in ipairs( result[ source_item_id ] ) do
      if existing.item_id == matched_item.item_id then return end
    end

    table.insert( result[ source_item_id ], matched_item )
  end

  local function add_expected_matches( result, name_index )
    for _, range in ipairs( TOGC_HEROIC_ITEM_ID_RANGES ) do
      for candidate_item_id = range[ 1 ], range[ 2 ] do
        local candidate_name = m.api.GetItemInfo( candidate_item_id )

        if candidate_name then
          local matches = name_index[ normalize_name( candidate_name ) ]

          for _, source_item_id in ipairs( matches or {} ) do
            if source_item_id ~= candidate_item_id then
              add_match( result, source_item_id, {
                item_id = candidate_item_id,
                item_name = candidate_name,
                expected = true
              } )
            end
          end
        else
          warm_item_cache( candidate_item_id )
        end
      end
    end
  end

  local function get_expected_matches_by_source_item_id( name_index )
    local result = {}

    if not use_item_names or not use_item_names.is_enabled() then return result end
    if name_index_dirty then build_name_index() end

    add_expected_matches( result, name_index )

    for _, matches in pairs( result ) do
      table.sort( matches, function( left, right ) return left.item_id < right.item_id end )
    end

    return result
  end

  local function merge_matched_items( observed_items, expected_items )
    local result = {}
    local seen = {}

    for _, item in ipairs( observed_items or {} ) do
      if not seen[ item.item_id ] then
        table.insert( result, item )
        seen[ item.item_id ] = true
      end
    end

    for _, item in ipairs( expected_items or {} ) do
      if not seen[ item.item_id ] then
        table.insert( result, item )
        seen[ item.item_id ] = true
      end
    end

    return result
  end

  local function add_name_mapping_rows( rows, reserve_type, data, match_history, expected_matches )
    local all_resolved = true
    local history_by_source = get_history_by_source_item_id( match_history )

    for item_id, item in pairs( data ) do
      local name = get_item_name( item_id, item )
      if not name then all_resolved = false end

      local function add_row( matched_item )
        table.insert( rows, {
          type = reserve_type,
          reserve_item_id = item_id,
          reserve_item_name = name,
          reserve_quality = item.quality,
          rollers = item.rollers and #item.rollers or nil,
          matched_item_id = matched_item and matched_item.item_id or nil,
          matched_item_name = matched_item and matched_item.item_name or nil,
          matched_item_expected = matched_item and matched_item.expected or false
        } )
      end

      local matched_items = merge_matched_items( history_by_source[ item_id ], expected_matches[ item_id ] )
      if matched_items and matched_items[ 1 ] then
        for _, matched_item in ipairs( matched_items ) do
          add_row( matched_item )
        end
      else
        add_row()
      end
    end

    return all_resolved
  end

  local function get_name_mapping_info()
    local rows = {}

    if use_item_names and use_item_names.is_enabled() and name_index_dirty then build_name_index() end

    local sr_expected_matches = get_expected_matches_by_source_item_id( sr_name_index )
    local hr_expected_matches = get_expected_matches_by_source_item_id( hr_name_index )
    local sr_resolved = add_name_mapping_rows( rows, "SR", softres_data, sr_name_match_history, sr_expected_matches )
    local hr_resolved = add_name_mapping_rows( rows, "HR", hardres_data, hr_name_match_history, hr_expected_matches )

    table.sort( rows, function( left, right )
      if left.type ~= right.type then return left.type > right.type end
      local left_name = left.reserve_item_name or ""
      local right_name = right.reserve_item_name or ""
      if left_name ~= right_name then return left_name < right_name end
      if left.reserve_item_id ~= right.reserve_item_id then return left.reserve_item_id < right.reserve_item_id end
      return (left.matched_item_id or 0) < (right.matched_item_id or 0)
    end )

    return {
      enabled = use_item_names and use_item_names.is_enabled() or false,
      all_resolved = sr_resolved and hr_resolved,
      rows = rows
    }
  end

  return {
    get = get,
    get_all_rollers = get_all_rollers,
    is_player_softressing = is_player_softressing,
    get_item_ids = get_item_ids,
    get_item_quality = get_item_quality,
    get_hr_item_ids = get_hr_item_ids,
    is_item_hardressed = is_item_hardressed,
    get_player_items = get_player_items,
    get_name_mapping_info = get_name_mapping_info,
    import = import,
    clear = clear,
    persist = persist
  }
end

m.SoftRes = M
return M
