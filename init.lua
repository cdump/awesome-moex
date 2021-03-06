--
-- MOEX module for Awesome WM
--
-- GitHub: https://github.com/cdump/awesome-calendar
--
-- Add to rc.lua:
-- local moex = require("moex")
-- ..
-- moex.addToWidget(widget, update_fcn, config)
--
-- Example:
-- moex.addToWidget(widgets.quotes.widget, widgets.quotes.update, {
--	[1] = {"currency", "EUR_RUB__TOM", "EUR" },
--	[2] = {"currency", "USD000UTSTOM", "USD" },
--	[3] = {"futures", "SiH6", "Si" }
-- })
--

local gears  = require("gears")
local dkjson = require("./moex/dkjson")
local string = string
local pairs = pairs
local tostring = tostring
local os = os
local print = print
local io = io
local capi = {
    mouse = mouse,
    screen = screen
}
local awful = require("awful")
local naughty = require("naughty")

local moex = {}

local urls = {
	["currency"] = "http://iss.moex.com/iss/engines/currency/markets/selt/boards/CETS/securities.json",
	["futures"] = "http://iss.moex.com/iss/engines/futures/markets/forts/securities.json",
	["crypto"] = "crypto",
}

local function get_quote(url, securities, cb)
    local full_url = ''
    if url == "crypto" then
        full_url = "https://www.okex.com/api/spot/v3/instruments/" .. securities .. "/ticker"
    else
        full_url = url .. "?iss.meta=off&iss.only=marketdata&securities=" .. securities .. "&marketdata.columns=UPDATETIME,OPEN,LOW,HIGH,LAST,CHANGE,LASTTOPREVPRICE"
    end
    local cmd = "curl -s --connect-timeout 1 -fsm 3 \"" .. full_url .. "\""
    awful.spawn.easy_async(cmd, function(stdout, stderr, reason, exit_code)
        local obj = dkjson.decode(stdout)
        if obj and obj.marketdata then
            cb(obj.marketdata.data)
        elseif obj and obj.instrument_id then
            cb({{
                '00:00:00',
                tonumber(obj.open_24h),
                tonumber(obj.low_24h),
                tonumber(obj.high_24h),
                tonumber(obj.last),
                tonumber(obj.last) - tonumber(obj.open_utc0),
                0
            }})
        else
            cb(nil)
        end
    end)
end

local function format_quote(last, change, sym)
	local text = string.format('%s%.2f <span color="#%s" font="sans 6">%s%.2f</span>',
        sym,
		last,
		change >= 0 and "33aa33" or "ee4444",
		change >= 0 and "+" or "",
		change)

	return text
end

local function update_view(data)
	local text
	local last_type
	local pos = 0
	for ppos,ticker in pairs(moex.tickers) do
		if last_type and last_type ~= ticker.typename then
			pos = 1
		else
			pos = pos + 1
		end
		last_type = ticker.typename
		if data[ticker.typename] then
			local d = data[ticker.typename][pos]
			if d ~= nil then
				moex.tickers[ppos].updtime = d[1]
				moex.tickers[ppos].open    = d[2]
				moex.tickers[ppos].low     = d[3]
				moex.tickers[ppos].high    = d[4]
				moex.tickers[ppos].last    = d[5]
				moex.tickers[ppos].change  = d[6]
			end
		end
	end

	for ppos,ticker in pairs(moex.tickers) do
		if ticker.last then
			if text then
				text = text .. " <span color='#888'>|</span> "
			else
				text = ""
			end
			text = text .. format_quote(ticker.last, ticker.change, ticker.sym)
		end
	end

	moex.update(text)
end

local function update_quotes()
    local updated = 0
	local data = {}

    local total = 0
	for typename, tickerstr in pairs(moex.bytypestr) do
        total = total + 1
    end

	for typename, tickerstr in pairs(moex.bytypestr) do
        get_quote(urls[typename], tickerstr, function(v)
            data[typename] = v
            updated = updated + 1
            if updated == total then
                update_view(data)
            end
        end)
	end
end


local function format_line(text, ftype, field, usecolor)
	local len = 9
	local line = ""
	for pos,data in pairs(moex.tickers) do
		if data[field] then
			local val = string.format(ftype, data[field])
			local color = "#cccccc"
			if usecolor then
				color = data.change > 0 and "#33aa33" or "#ee4444"
			end
			line = line .. "<span color='" .. color .. "'>" .. val .. "</span>" .. string.rep(' ', len - #val) .. " | "
		end
	end
	return text .. string.rep(' ', 6 - #text) .. " | " .. line .. "\n"
end

local function get_naughty_text()
	local text = "<span color='#222222'><b>"
	text = text .. format_line("", "%s", "sym")
	text = text .. "</b></span>"

	-- text = text .. ".--------+--------+--------+--------+--------+--------.\n"
	text = text .. format_line("Last:", "%.2f", "last", true)
	text = text .. format_line("Diff:", "%s", "change", true)
	text = text .. format_line("Upd:", "%s", "updtime")
	text = text .. format_line("Low:", "%.2f", "low")
	text = text .. format_line("Open:", "%.2f", "open")
	text = text .. format_line("High:", "%.2f", "high")

	return "<span font_desc='monospace'>" .. text .. "</span>"
end

local function addToWidget(mywidget, update, tickers)
	moex.widget = mywidget
	moex.update = update

	moex.tickers = {}
	moex.bytypestr = {}

	for pos,data in pairs(tickers) do
		local ticker = {}

		ticker.pos = pos
		ticker.typename = data[1]
		ticker.name = data[2]
		ticker.sym = data[3]

		ticker.updtime = nil
		ticker.open = 0
		ticker.low = 0
		ticker.high = 0
		ticker.last = 0
		ticker.change = 0

		if moex.bytypestr[ticker.typename] == nil then
			moex.bytypestr[ticker.typename] = ""
		else
			moex.bytypestr[ticker.typename] = moex.bytypestr[ticker.typename] .. ","
		end
		moex.bytypestr[ticker.typename] = moex.bytypestr[ticker.typename] .. ticker.name

		moex.tickers[pos] = ticker
	end

	local timer_quotes = gears.timer { timeout = 60 }
	timer_quotes:connect_signal("timeout", update_quotes)
	timer_quotes:start()
	timer_quotes:emit_signal("timeout")

    mywidget:connect_signal('mouse::enter', function ()
		moex.notify = naughty.notify({
            text = get_naughty_text(),
			position = "bottom_right",
            timeout = 0,
            hover_timeout = 0.5,
            screen = capi.mouse.screen
        })
	end)
	mywidget:connect_signal('mouse::leave', function () naughty.destroy(moex.notify) end)
	mywidget:buttons(awful.util.table.join( awful.button({ }, 1, update_quotes)))
end


return {
    addToWidget = addToWidget,
}
