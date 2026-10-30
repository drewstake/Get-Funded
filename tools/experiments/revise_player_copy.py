"""Apply reviewed literal-only copy edits; refuse missing anchors and record every change."""
import sys
from pathlib import Path
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents if (p / 'build/place-manifest.json').is_file()) / 'tools'))
from source_paths import source_file
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
changes = []

def edit(file, pairs):
    path = source_file(ROOT, file)
    source = path.read_text(encoding='utf-8')
    for old, new in pairs:
        assert old in source, (file, old)
        count = source.count(old)
        source = source.replace(old, new)
        changes.append(dict(file=file, before=old, after=new, occurrences=count))
    path.write_text(source, encoding='utf-8', newline='\n')

edit('TerminalUI.luau', [
 ('"Keep growing your balance"', '"Title collection complete"'),
 ('"Trade · Grow · Earn titles"', '"Build your record. Earn your rank."'),
 ('"All milestones earned"', '"Every title earned"'),
 ('"A free $10,000 restart is available after your account fails."', '"Restart free with $10,000 after your account fails."'),
 ('"Closing remaining positions. Restart unlocks once liquidation finishes."', '"Closing your remaining positions. Restart when they have all closed."'),
 ('"Enter a positive whole quantity."', '"Enter a whole number of contracts, starting at 1."'),
 ('"That\'s more than your account allows right now. Maximum currently available: "', '"Order too large. Available now: "'),
 ('..max.." "..s.Contract.."."', '..max.." "..s.Contract.." contracts."'),
 ('"Enter a valid finite number."', '"Enter a valid price."'),
 ('"OPEN GAIN / LOSS"', '"OPEN PROFIT"'),
 ('"Equity reached $0"', '"Equity fell to $0 or below"'),
 ('"No completed trades yet"', '"No closed trades yet"'),
 ('"Choose a contract and place a order."', '"Choose a market, set your quantity, then Buy or Sell."'),
 ('"Limit and protective orders appear here."', '"Pending orders, stop loss and take profit appear here."'),
 ('"Close a position to review your result."', '"Close a trade to see its realized profit here."'),
 ('{"Instrument","Side","Qty","Entry","Result","Action"}', '{"Market","Side","Qty","Entry","Open profit","Action"}'),
 ('{"Instrument","Order","Qty","Price","Status","Action"}', '{"Market","Order","Qty","Price","Status","Action"}'),
 ('{"Instrument","Qty","Entry","Exit","Result","Closed"}', '{"Market","Qty","Entry","Exit","Realized profit","Closed"}'),
 ('"Estimated total loss  "', '"Estimated stop loss  "'),
 ('"No stop loss configured"', '"Stop loss is off"'),
 ('"Enter a valid positive amount."', '"Enter an amount greater than $0."'),
 ('"Stop Loss ($)"', '"Stop loss ($)"'),
 ('"Take Profit ($)"', '"Take profit ($)"'),
 ('"Fills at the current market price"', '"Trades now at available prices"'),
 ('"Fills at your limit price or better"', '"Trades at your price or better"'),
 ('"Total dollars for your selected quantity"', '"Total amounts for this order"'),
 ('"Next order · rounded to valid prices · fills may vary"', '"Next order · prices round to ticks · fills may vary"'),
 ('"Save settings"', '"Save"'),
 ('"Current result"', '"Open profit"'),
 ('"Closing adds the final gain to your balance or subtracts the loss."', '"Closing locks in the filled trade\'s profit or loss. The final amount may differ."'),
 ('"Select a contract"', '"Choose a market"'),
 ('"Help & guided first trade"', '"How to play"'),
 ('"Settings & sound"', '"Settings"'),
 ('"Equity reached $0. Equity is your balance plus the gain or loss on open trades."', '"Your equity fell to $0 or below. Equity is your balance plus open profit, including losses."'),
 ('"This run: "..Market.Signed(row.Realized or 0).." closed trading result."', '"Realized profit this account: "..Market.Signed(row.Realized or 0)'),
 ('"Start again with $10,000 in-game money. Your titles, milestone rewards and lifetime trading results are kept. Losses stay in lifetime net profit."', '"Restart free with $10,000 in-game money. Keep your ranks, titles and lifetime totals. Losses still count toward lifetime net profit."'),
 ('"Workspace, sound and market session"', '"Chart and sound"'),
 ('"Entry, stop and target lines"', '"Entry, stop loss and take profit"'),
 ('"Prices and slippage come from executions in the order book. Regime: "', '"Prices can change before an order fills. Market conditions: "'),
 ('"Pick an instrument"', '"Choose your market"'),
 ('"Open the contract list and choose a market. BX, the Blox 500, is a good first pick."', '"Open the market list. Choose BX for the Blox 500, BT for tech or BG for gold."'),
 ('"Set your size"', '"Set your quantity"'),
 ('"Start with 1 contract. Your balance starts at $10,000 in-game money. Equity is balance plus open gain/loss. The account fails at $0 equity."', '"Start with 1 contract. More contracts mean bigger gains and losses for the same price move."'),
 ('"BUY if you expect the price to rise, SELL if you expect it to fall. Your stop loss and take profit attach automatically."', '"BUY to profit from a rise. SELL to profit from a fall. Stop loss and take profit attach when switched on."'),
 ('"When you\'re ready, close it. Closing adds the final gain to your balance or subtracts the loss. Only closed trades count toward your goals."', '"Close to lock in your profit or loss. The filled result updates your balance and counts toward your goals."'),
 ('"First profit milestone"', '"First trade complete"'),
 ('"All money here is in-game. Start with $10,000, trade, grow your balance and earn permanent titles. Choose a market to begin."', '"Your $10,000 starting balance is in-game money. Open the market list and choose where to trade."'),
 ('"Closed result: "', '"Realized profit: "'),
 ('"Your balance now includes that result. "', '"It now counts toward your goals. "'),
 ('"All milestones earned!"', '"Every title is yours."'),
 ('"GUIDED FIRST TRADE · "', '"FIRST TRADE · "'),
 ('"Milestone reached: "..event.Name.." · Title earned: "..event.Title', '"Title earned: "..event.Title.." · "..event.Name'),
 ('"Rank unlocked: "', '"Rank up: "'),
 ('"EXCHANGE / PAUSED"or "EXCHANGE / CONNECTING"', '"Trading paused"or "Connecting to the exchange…"'),
 ('"Local / not saved · "', '"Not saved · "'),
 ('"New Trader"', '"Market Rookie"'),
 ('"Order filled - take profit"', '"Take profit filled"'),
 ('"Order filled - stop loss"', '"Stop loss filled"'),
 ('"Order closed"', '"Trade closed"'),
])

edit('ProgressionConfig.luau', [
 ('Name="Complete ', 'Name="Close '),
 ('Name="Earn $', 'Name="Reach $'),
])

edit('ProgressView.luau', [
 ('"Ranks mark your journey. Titles celebrate your achievements. Both stay yours."', '"Build your record. Earn ranks and titles that stay yours."'),
 ('"Your progression is loading…"', '"Loading your ranks and titles…"'),
 ('"ACCOUNT CLOSED · LIFETIME NET PROFIT"or "ACCOUNT ACTIVE · LIFETIME NET PROFIT"', '"LIFETIME NET PROFIT"or "LIFETIME NET PROFIT"'),
 ('"Collection complete!"', '"Every title is yours"'),
 ('"Every achievement title is yours. Keep building your legacy."', '"You reached every title milestone in Get Funded!"'),
 ('"Closed trades count. Unlocks are permanent."', '"Earned titles stay yours."'),
 ('"Three paths. Bigger milestones. Each column unlocks from top to bottom."', '"Close trades, earn wins and build lifetime net profit. Each goal earns a title."'),
 ('"Meet every requirement to rank up. Earned ranks never fall after a loss."', '"Meet all three lifetime goals to rank up. Losses never take an earned rank away."'),
 ('"Complete every requirement:"', '"Meet all three goals:"'),
 ('"Earned before goal update"', '"Kept from an earlier goal"'),
 ('"Unlocked forever"', '"Yours to keep"'),
 ('"Completed trades"', '"Closed trades"'),
 ('.." completed"', '.." closed"'),
])

edit('FundedAccounts.luau', [
 ('"Your $10,000 in-game trading balance is ready."', '"Your $10,000 account is ready. Choose a market to begin."'),
 ('"This restart is out of date. Review your current run."', '"Your account has changed. Check it before restarting."'),
 ('"A free restart is available after equity reaches $0 and all positions close."', '"Restart free after your account fails and all positions and orders close."'),
 ('"Please wait before restarting again. Your history and rewards are safe."', '"Restart limit reached. Wait for a restart to become available; your progress is kept."'),
 ('"Fresh start: $10,000 in-game money. Your titles and lifetime results are kept."', '"Account restarted with $10,000. Your ranks, titles and lifetime totals are kept."'),
 ('"Wait for your account."', '"Wait for your account to load."'),
 ('"Enter valid stop-loss and take-profit amounts and switches."', '"Check your stop loss and take profit settings. Use amounts greater than $0."'),
 ('"Your story starts here"', '"Your first title awaits"'),
])

edit('StatsView.luau', [
 ('"Closed trading results for your current account. Starting money is excluded."', '"Current account only. Starting money and open profit are excluded."'),
 ('") remain in Total P&L. Ratios are unavailable until the current account has a complete breakdown."', '") are included in realized profit. Ratios need a complete trade breakdown."'),
 ('"Your trading performance at a glance"', '"Every closed trade, measured."'),
 ('". Your saved results are safe; stats appear as soon as the exchange is ready."', '". Stats will load when the exchange is ready."'),
 ('"Fetching your current account\'s results from the exchange server."', '"Loading closed trades from your current account."'),
 ('"Your results are saved. Return to Trade while the exchange connects."', '"Return to Trade while the exchange connects."'),
 ('"No completed trades in this view yet. Close a position and its result appears here within a second."', '"No closed trades in this account yet. Close a trade to add its result."'),
 ('"Net realized profit or loss from your current account\'s closed trades. Open positions and starting money are excluded."', '"Realized profit is the net profit or loss from closed trades in this account. It excludes open profit and starting money. Progress and Leaderboard use lifetime net profit across all accounts, including restarts."'),
 ('"Winning closing fills divided by all closing fills. Break-even fills count in the denominator. Partial closes count per closing fill, matching Trade History."', '"Profitable closed trades divided by all closed trades, including break-even trades. Each closing fill counts as one trade, even when it closes only part of a position. Each has a row in Trade history."'),
 ('"Average winning P&L divided by the absolute average losing P&L. Both dollar averages are shown. ∞ means positive wins with no losses; — means no usable denominator."', '"Average profit per winning trade divided by average loss per losing trade. Both amounts are shown below. ∞ means wins with no losses. — means there is not enough data to calculate the ratio."'),
 ('"Sum of positive closed P&L divided by the absolute sum of negative closed P&L. ∞ means positive gains and zero losses. With no gains or losses, the ratio is unavailable."', '"Total profit from winning trades divided by total losses from losing trades. ∞ means profits with no losses. — means there are no profits or losses yet."'),
])

edit('StatsPieces.luau', [
 ('Total P&L', 'Realized profit'),
 ('Closed trades only', 'Current account · closed trades'),
 ('Best day % of total profit', 'Best day share'),
 ('"Net realized results from your current account\'s closed trades. Excludes open positions and starting capital."', '"Net profit or loss from closed trades in this account. Excludes open profit and starting money."'),
 ('"Winning closing fills divided by all closing fills. Break-even fills stay in the denominator."', '"Profitable closed trades divided by all closed trades, including break-even trades. Each closing fill counts as one trade."'),
 ('"Average winning P&L divided by absolute average losing P&L. Infinity means positive gains with no losses."', '"Average profit per winning trade divided by average loss per losing trade. ∞ means wins with no losses."'),
 ('"Profitable UTC days divided by all days with closing fills in your current account."', '"Profitable days divided by days with closed trades in this account. Days run from midnight to midnight UTC. Days without trades do not count."'),
 ('"Gross positive P&L divided by absolute gross negative P&L. Bar lengths are shares of their combined magnitude, not the ratio itself."', '"Total profits divided by total losses from closed trades. The bar compares those two totals."'),
 ('"Highest daily net profit divided by total net profit. Can exceed 100%. Requires complete dates and positive total net profit."', '"Your best day\'s net profit divided by this account\'s realized profit. Losses on other days can push this above 100%. Needs complete trade dates and realized profit above $0."'),
 ('"Requires positive total net profit"', '"Needs realized profit above $0"'),
 ('"Best daily net ÷ total net profit"', '"Best daily net profit ÷ realized profit"'),
 ('positive total net profit.', 'realized profit above $0.'),
])

edit('LeaderboardView.luau', [
 ('"Top 100 · lifetime net trading profit"', '"Top 100 · lifetime net profit"'),
 ('"This server · lifetime net trading profit"', '"This server · lifetime net profit"'),
 ('"Lifetime net trading profit"', '"Lifetime net profit"'),
 ('"NET PROFIT"', '"LIFETIME NET PROFIT"'),
 ('"Rank updating…"', '"Loading rank…"'),
 ('"Fetching standings…"', '"Loading standings…"'),
 ('"Your progress is safe. Tap Refresh to try again."', '"Could not load standings. Select Refresh to try again."'),
 ('"Close a trade to join the leaderboard!"', '"No standings yet. Close a trade to join."'),
 ('"Standings unavailable. Tap Refresh."', '"Standings unavailable. Select Refresh."'),
 ('"Saved results · refresh to update"', '"Earlier standings · refresh to update"'),
])
edit('LeaderboardClient.luau', [('"Complete a trade to join"', '"Close a trade to join"')])
edit('LeaderboardRanking.luau', [('"Complete a trade to join"', '"Close a trade to join"')])
edit('MarketClient.luau', [
 ('"Enter valid stop-loss and take-profit amounts and switches."', '"Check your stop loss and take profit settings. Use amounts greater than $0."'),
 ('"Exchange is connecting."', '"Connecting to the exchange. Try again in a moment."'),
 ('"Waiting for exchange."', '"Connecting to the exchange. Try again in a moment."'),
])
edit('TradeProtection.luau', [
 ('"Choose a positive whole quantity."', '"Enter a whole number of contracts, starting at 1."'),
 ('"Protection must be a positive dollar amount within 10,000 ticks for this quantity."', '"Enter a protection amount above $0 and within 10,000 price ticks for this quantity."'),
])
edit('MarketEngine.luau', [
 ('"Invalid instrument, side or quantity. Use a positive whole number."', '"Choose a market, Buy or Sell, and a whole number of contracts starting at 1."'),
 ('"Account depleted. Maximum currently available: 0 "', '"Account failed. Maximum currently available: 0 "'),
 ('"Account liquidation in progress. Maximum currently available: 0 "', '"Closing failed account positions. Maximum currently available: 0 "'),
 ('"Account depleted. Limit order cannot be changed."', '"Account failed. This limit order cannot be changed."'),
 ('" price must use the instrument tick size."', '" price must match the market\'s price increments (ticks)."'),
 ('"Limit price must use the instrument tick size."', '"Limit price must match the market\'s price increments (ticks)."'),
 ('"Protection price must use the instrument tick size."', '"Protection price must match the market\'s price increments (ticks)."'),
 ('"Keep SL beyond the current price on the loss side."', '"Place stop loss beyond the current price in the losing direction."'),
 ('"Keep TP beyond the current price on the profit side."', '"Place take profit beyond the current price in the winning direction."'),
 ('field=="Stop" and "SL" or "TP",price)', 'field=="Stop" and "Stop loss" or "Take profit",price)'),
])
edit('ChartView.luau', [
 ('"Loading executed trades"', '"Loading price history…"'),
 ('"Waiting for executed trades."', '"Waiting for market trades."'),
 ('"Candles appear as soon as the exchange sends executed trades."', '"Candles appear when market trades arrive."'),
 ('"Limit update not confirmed. Restored the last server price."', '"Limit change not confirmed. Showing its last confirmed price."'),
 ('"Update not yet confirmed. Showing the last server price."', '"Change not confirmed. Showing the last confirmed price."'),
])
edit('MarketServer.server.luau', [
 ('"Your trading account changed after depletion. Review your current run and retry."', '"Your account has restarted. Check the current account and try again."'),
 ('"Your trading account changed. Review your current run and retry."', '"Your account has changed. Check it and try again."'),
 ('". All progress cleared; fresh $10,000 account ready."', '". All trading history, ranks, titles and settings cleared. New $10,000 account ready."'),
 ('"The owner reset your Get Funded! data. Rejoin for a fresh $10,000 account."', '"The owner reset your Get Funded! data, including ranks, titles and trading history. Rejoin to start with $10,000 in-game money."'),
])

out=ROOT/'output/copy-review-20261002'
out.mkdir(parents=True,exist_ok=True)
(out/'copy-changes.json').write_text(json.dumps(changes,indent=2,ensure_ascii=False),encoding='utf-8')
print(f'{len(changes)} reviewed replacements across {len(set(c["file"] for c in changes))} files')
