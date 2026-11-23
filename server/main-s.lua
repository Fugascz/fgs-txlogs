local config = FGS_TXLOGS_CONFIG or {}
local configuredWebhooks = type(config.webhooks) == 'table' and config.webhooks or {}
local DEFAULT_WEBHOOK_URL = type(config.defaultWebhook) == 'string' and config.defaultWebhook or ''

local function getConfiguredWebhook(webhookKey)
    local webhook = configuredWebhooks[webhookKey]
    if type(webhook) == 'string' and webhook ~= '' then
        return webhook
    end

    return DEFAULT_WEBHOOK_URL
end

local WEBHOOKS = {
    playerWarned = getConfiguredWebhook('playerWarned'),
    playerKicked = getConfiguredWebhook('playerKicked'),
    playerBanned = getConfiguredWebhook('playerBanned'),
    actionRevoked = getConfiguredWebhook('actionRevoked'),
    playerDirectMessage = getConfiguredWebhook('playerDirectMessage'),
    announcement = getConfiguredWebhook('announcement'),
    whitelistPlayer = getConfiguredWebhook('whitelistPlayer'),
    whitelistPreApproval = getConfiguredWebhook('whitelistPreApproval')
}
local REQUEST_INTERVAL_MS = 1100
local MAX_QUEUE_SIZE = 200
local MAX_RETRIES = 3
local queue = {}
local sending = false
local nextRequestAt = 0
local timerScheduled = false

local function truncate(value, limit)
    if value == nil or value == '' then
        value = 'Není k dispozici'
    else
        value = tostring(value)
    end

    if #value <= limit then
        return value
    end

    return value:sub(1, limit - 3) .. '...'
end

local function formatIdentifiers(identifiers)
    if type(identifiers) ~= 'table' or #identifiers == 0 then
        return 'Není k dispozici'
    end

    local values = {}
    for _, identifier in ipairs(identifiers) do
        values[#values + 1] = tostring(identifier)
    end

    return truncate(table.concat(values, '\n'), 1024)
end

local function makeField(name, value, inline)
    return {
        name = truncate(name, 256),
        value = truncate(value, 1024),
        inline = inline == true
    }
end

local function fitFields(title, fields, footer)
    local remaining = 5900 - #title - #footer
    local result = {}

    for _, field in ipairs(fields) do
        local valueLimit = math.min(1024, remaining - #field.name - 1)
        if valueLimit < 1 then
            break
        end

        field.value = truncate(field.value, valueLimit)
        result[#result + 1] = field
        remaining = remaining - #field.name - #field.value
    end

    return result
end

local function processQueue()
    if sending or #queue == 0 then
        return
    end

    local waitTime = nextRequestAt - GetGameTimer()
    if waitTime > 0 then
        if not timerScheduled then
            timerScheduled = true
            SetTimeout(waitTime, function()
                timerScheduled = false
                processQueue()
            end)
        end
        return
    end

    timerScheduled = false
    sending = true
    local entry = table.remove(queue, 1)

    PerformHttpRequest(entry.webhook, function(statusCode, _, headers)
        statusCode = tonumber(statusCode) or 0

        if statusCode == 429 and entry.retries < MAX_RETRIES then
            entry.retries = entry.retries + 1
            table.insert(queue, 1, entry)
            local retryAfter = tonumber(headers and (headers['retry-after'] or headers['Retry-After'])) or 2
            nextRequestAt = GetGameTimer()
                + math.min(math.max(retryAfter * 1000, REQUEST_INTERVAL_MS), 60000)
            sending = false
            processQueue()
            return
        end

        if statusCode < 200 or statusCode >= 300 then
            print(('[fgs-txlogs] Discord webhook request failed with HTTP %s.'):format(statusCode))
        end

        nextRequestAt = GetGameTimer() + REQUEST_INTERVAL_MS
        sending = false
        processQueue()
    end, 'POST', json.encode(entry.payload), {
        ['Content-Type'] = 'application/json'
    })
end

local function sendLog(webhookKey, title, fields)
    local webhook = WEBHOOKS[webhookKey]
    if not webhook or webhook == '' then
        return
    end

    if #queue >= MAX_QUEUE_SIZE then
        print('[fgs-txlogs] Log queue is full; the newest event was discarded.')
        return
    end

    title = truncate(title, 256)
    local footer = os.date('%d. %m. %Y %H:%M:%S') .. ' - fgs-txlogs'

    queue[#queue + 1] = {
        webhook = webhook,
        retries = 0,
        payload = {
            username = 'fgs-txlogs - txAdmin Event Logs',
            allowed_mentions = {
                parse = {}
            },
            embeds = {
                {
                    color = 16748800,
                    title = title,
                    fields = fitFields(title, fields, footer),
                    footer = {
                        text = footer
                    }
                }
            }
        }
    }

    processQueue()
end

local function registerLog(eventName, webhookKey, handler)
    AddEventHandler(eventName, function(data)
        if type(data) ~= 'table' then
            print(('[fgs-txlogs] Ignored malformed txAdmin event: %s.'):format(eventName))
            return
        end

        sendLog(webhookKey, handler(data))
    end)
end

registerLog('txAdmin:events:playerWarned', 'playerWarned', function(data)
    return '⚠️ Hráč byl varován', {
        makeField('ID hráče', data.target),
        makeField('Administrátor', data.author),
        makeField('Důvod varování', data.reason),
        makeField('Action ID', data.actionId)
    }
end)

registerLog('txAdmin:events:playerKicked', 'playerKicked', function(data)
    return '💥 Hráč byl odpojen', {
        makeField('ID hráče', data.target),
        makeField('Administrátor', data.author),
        makeField('Důvod odpojení', data.reason)
    }
end)

registerLog('txAdmin:events:playerBanned', 'playerBanned', function(data)
    return '🚫 Hráč byl zabanován', {
        makeField('Hráč', data.targetName),
        makeField('Administrátor', data.author),
        makeField('Důvod banu', data.reason),
        makeField('Ban ID', data.actionId),
        makeField('Expirace banu', data.durationTranslated),
        makeField('Identifikátory', formatIdentifiers(data.targetIds)),
        makeField('HWID', formatIdentifiers(data.targetHwids))
    }
end)

registerLog('txAdmin:events:actionRevoked', 'actionRevoked', function(data)
    return '📢 Administrátor odvolal akci', {
        makeField('Action ID', data.actionId),
        makeField('Typ akce', data.actionType),
        makeField('Důvod odvolání', data.actionReason),
        makeField('Autor akce', data.actionAuthor),
        makeField('Odvolal', data.revokedBy),
        makeField('Hráč', data.playerName),
        makeField('Identifikátory', formatIdentifiers(data.playerIds)),
        makeField('HWID', formatIdentifiers(data.playerHwids))
    }
end)

registerLog('txAdmin:events:playerDirectMessage', 'playerDirectMessage', function(data)
    local targetId = tonumber(data.target)
    local playerName = targetId and GetPlayerName(targetId) or nil
    local target = playerName
        and ('[%s] %s'):format(data.target, playerName)
        or data.target

    return '💬 Administrátor poslal soukromou zprávu', {
        makeField('Hráč', target),
        makeField('Administrátor', data.author),
        makeField('Zpráva', data.message)
    }
end)

registerLog('txAdmin:events:announcement', 'announcement', function(data)
    return '🔔 Administrátor poslal oznámení serveru', {
        makeField('Administrátor', data.author),
        makeField('Zpráva', data.message)
    }
end)

registerLog('txAdmin:events:whitelistPlayer', 'whitelistPlayer', function(data)
    return '❗ Administrátor upravil whitelist hráče', {
        makeField('Akce', data.action == 'added' and 'Přidal whitelist' or 'Odebral whitelist'),
        makeField('Hráč', data.playerName),
        makeField('Licence hráče', data.license and ('license:%s'):format(data.license)),
        makeField('Administrátor', data.adminName)
    }
end)

registerLog('txAdmin:events:whitelistPreApproval', 'whitelistPreApproval', function(data)
    return '❗ Administrátor upravil předběžné schválení whitelistu', {
        makeField('Akce', data.action == 'added' and 'Přidal schválení' or 'Odebral schválení'),
        makeField('Hráč', data.playerName or 'Jméno není známo'),
        makeField('Licence hráče', data.license and ('license:%s'):format(data.license)),
        makeField('Administrátor', data.adminName)
    }
end)

local function isValidWebhook(url)
    return url:match('^https://discord%.com/api/webhooks/')
        or url:match('^https://discordapp%.com/api/webhooks/')
end

local enabledWebhookCount = 0
for webhookKey, webhook in pairs(WEBHOOKS) do
    if webhook ~= '' then
        if isValidWebhook(webhook) then
            enabledWebhookCount = enabledWebhookCount + 1
        else
            print(('[fgs-txlogs] Invalid webhook URL for %s; this event will not be logged.'):format(webhookKey))
            WEBHOOKS[webhookKey] = ''
        end
    end
end

if enabledWebhookCount == 0 then
    print('[fgs-txlogs] No Discord webhook configured. Add URLs to config.lua.')
end
