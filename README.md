# fgs-txlogs

**Autor:** Fugascz

Resource pro odesílání událostí z txAdmin do Discordu prostřednictvím webhooku. Události zachytává na serveru a odesílá jako Discord embedy.

## Požadavky

- FiveM server s txAdmin
- Platný Discord webhook pro cílový kanál

## Nastavení webhooků

Webhooky se nastavují přímo v `config.lua`. Každý typ události má vlastní položku `webhooks`, takže ji lze posílat do samostatného textového kanálu. Vlož URL do uvozovek:

```lua
FGS_TXLOGS_CONFIG = {
    defaultWebhook = '',
    webhooks = {
        playerWarned = 'https://discord.com/api/webhooks/ID/TOKEN',
        playerKicked = 'https://discord.com/api/webhooks/ID/TOKEN',
        playerBanned = 'https://discord.com/api/webhooks/ID/TOKEN',
        actionRevoked = 'https://discord.com/api/webhooks/ID/TOKEN',
        playerDirectMessage = 'https://discord.com/api/webhooks/ID/TOKEN',
        announcement = 'https://discord.com/api/webhooks/ID/TOKEN',
        whitelistPlayer = 'https://discord.com/api/webhooks/ID/TOKEN',
        whitelistPreApproval = 'https://discord.com/api/webhooks/ID/TOKEN'
    }
}
```

`defaultWebhook` je nepovinná společná URL pro události bez vlastního webhooku. Pokud ji nepoužiješ, nech ji prázdnou; prázdné položky se nebudou logovat. Stejnou URL můžeš přiřadit více událostem. Individuální URL má vždy přednost před výchozí.

## Zaznamenávané události

- varování hráče,
- odpojení hráče administrátorem,
- ban hráče,
- odvolání administrátorské akce,
- soukromá zpráva hráči,
- oznámení serveru,
- změna whitelistu,
- změna předběžného schválení whitelistu.

Zprávy obsahují dostupné údaje předané txAdminem. Ban a odvolání akce mohou obsahovat identifikátory hráče a HWID; soukromé zprávy a oznámení obsahují jejich text. Přístup k Discord kanálu s logy proto omez pouze na důvěryhodné osoby.

## Odesílání a diagnostika

Události se řadí do omezené fronty a odesílají postupně s odstupem, aby se omezily Discord rate limity. Odpověď HTTP 429 se několikrát opakuje podle hlavičky `Retry-After`. Chyby požadavku a přetečení fronty se hlásí do serverové konzole; samotný webhook ani jeho token se nelogují.

Pokud se logy neodesílají:

1. Zkontroluj URL v `config.lua` a ověř, že daná událost má webhook nebo že je nastavený `defaultWebhook`.
2. Ověř v serverové konzoli, že se resource spustil a webhook nebyl odmítnut.
3. Ověř platnost webhooku a oprávnění bota/webhooku posílat zprávy do cílového kanálu.
4. Proveď příslušnou akci přes txAdmin a sleduj HTTP chyby v serverové konzoli.
