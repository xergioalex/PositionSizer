//+------------------------------------------------------------------+
//|                                       Position Sizer Trading.mqh |
//|                                  Copyright © 2024, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#include <stdlib.mqh>

//+------------------------------------------------------------------+
//| Main trading function.                                           |
//+------------------------------------------------------------------+
void Trade()
{
    string Commentary = "";

    if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
        Alert("AutoTrading disabled! Please enable AutoTrading.");
        return;
    }

    if ((WarningSL != "") && (!sets.DoNotApplyStopLoss)) // Too close or wrong value.
    {
        Alert("Stop-loss problem: " + WarningSL);
        return;
    }

    if (OutputPositionSize <= 0)
    {
        Alert("Wrong position size value!");
        return;
    }

    double TP[], TPShare[]; // Mimics sets.TP[] and sets.TPShare[], but always includes the main TP too.

    ArrayResize(TP, sets.TakeProfitsNumber);
    ArrayResize(TPShare, sets.TakeProfitsNumber);

    if (sets.TakeProfitsNumber > 1)
    {
        Print("Multiple TP volume share sum = ", TotalVolumeShare, ".");
        if ((TotalVolumeShare < 99) || (TotalVolumeShare > 100))
        {
            Alert("Incorrect volume sum for multiple TPs - not taking any trades.");
            return;
        }
        for (int i = 0; i < sets.TakeProfitsNumber; i++)
        {
            TP[i] = sets.TP[i];
            TPShare[i] = sets.TPShare[i];
        }
    }
    else
    {
        // No multiple TPs, use single TP for 100% of volume.
        TP[0] = sets.TakeProfitLevel;
        TPShare[0] = 100;
    }

    if (sets.Commentary != "") Commentary = sets.Commentary;

    if (sets.CommentAutoSuffix) Commentary += IntegerToString((int)TimeLocal());

    if ((sets.DisableTradingWhenLinesAreHidden) && (!sets.ShowLines))
    {
        Alert("Not taking a trade - lines are hidden and panel is set not to trade when they are hidden.");
        return;
    }

    RefreshRates();

    if (sets.MaxSpread > 0)
    {
        int spread = (int)((Ask - Bid) / Point);
        if (spread > sets.MaxSpread)
        {
            Alert("Not taking a trade - current spread (", spread, ") > maximum spread (", sets.MaxSpread, ").");
            return;
        }
    }

    if (sets.MaxEntrySLDistance > 0)
    {
        int CurrentEntrySLDistance = (int)(MathAbs(sets.StopLossLevel - sets.EntryLevel) / Point);
        if (CurrentEntrySLDistance > sets.MaxEntrySLDistance)
        {
            Alert("Not taking a trade - current Entry/SL distance (", CurrentEntrySLDistance, ") > maximum Entry/SL distance (", sets.MaxEntrySLDistance, ").");
            return;
        }
    }

    if (sets.MinEntrySLDistance > 0)
    {
        int CurrentEntrySLDistance = (int)(MathAbs(sets.StopLossLevel - sets.EntryLevel) / Point);
        if (CurrentEntrySLDistance < sets.MinEntrySLDistance)
        {
            Alert("Not taking a trade - current Entry/SL distance (", CurrentEntrySLDistance, ") < minimum Entry/SL distance (", sets.MinEntrySLDistance, ").");
            return;
        }
    }

    if ((sets.MaxNumberOfTradesTotal > 0) || (sets.MaxNumberOfTradesPerSymbol > 0))
    {
        int total = OrdersTotal();
        int cnt = 0, persymbol_cnt = 0;
        for (int i = 0; i < total; i++)
        {
            if (!OrderSelect(i, SELECT_BY_POS)) continue;
            if ((sets.MagicNumber != 0) && (OrderMagicNumber() != sets.MagicNumber)) continue;
            if (OrderSymbol() == Symbol()) persymbol_cnt++;
            cnt++;
        }
        if ((cnt + sets.TakeProfitsNumber > sets.MaxNumberOfTradesTotal) && (sets.MaxNumberOfTradesTotal > 0))
        {
            Alert("Not taking a trade - current total # of trades (", cnt, ") + number of trades in execution (", sets.TakeProfitsNumber, ") > maximum total number of trades allowed (", sets.MaxNumberOfTradesTotal, ").");
            return;
        }
        if ((persymbol_cnt + sets.TakeProfitsNumber > sets.MaxNumberOfTradesPerSymbol) && (sets.MaxNumberOfTradesPerSymbol > 0))
        {
            Alert("Not taking a trade - current # of trades per symbol (", persymbol_cnt, ") + number of trades in execution (", sets.TakeProfitsNumber, ") > maximum number of trades per symbol allowed (", sets.MaxNumberOfTradesPerSymbol, ").");
            return;
        }
    }
    
    if (sets.MaxRiskTotal > 0)
    {
        CalculatePortfolioRisk(CALCULATE_RISK_FOR_TRADING_TAB_TOTAL);
        double risk;
        if (PortfolioLossMoney != DBL_MAX)
        {
            risk = (PortfolioLossMoney + OutputRiskMoney) / AccSize * 100;
            if (risk > sets.MaxRiskTotal)
            {
                Alert("Not taking a trade - total potential risk (", DoubleToString(risk, 2), ") >= maximum total risk allowed (", DoubleToString(sets.MaxRiskTotal, 2), ").");
                return;
            }
        }
        else
        {
            Alert("Not taking a trade - infinite total potential risk.");
            return;
        }
    }
    if (sets.MaxRiskPerSymbol > 0)
    {
        CalculatePortfolioRisk(CALCULATE_RISK_FOR_TRADING_TAB_PER_SYMBOL);
        double risk;
        if (PortfolioLossMoney != DBL_MAX)
        {
            risk = (PortfolioLossMoney + OutputRiskMoney) / AccSize * 100;
            if (risk > sets.MaxRiskPerSymbol)
            {
                Alert("Not taking a trade - potential risk per symbol (", DoubleToString(risk, 2), ") >= maximum risk per symbol allowed (", DoubleToString(sets.MaxRiskPerSymbol, 2), ").");
                return;
            }
        }
        else
        {
            Alert("Not taking a trade - infinite potential risk per symbol.");
            return;
        }
    }
    
    ENUM_SYMBOL_TRADE_EXECUTION Execution_Mode = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_EXEMODE);
    string warning_suffix = "";
    if ((Execution_Mode == SYMBOL_TRADE_EXECUTION_MARKET) && (IgnoreMarketExecutionMode) && (sets.EntryType == Instant)) warning_suffix = ", but IgnoreMarketExecutionMode = true. Switch to false if trades aren't executing.";
    Print("Execution mode: ", EnumToString(Execution_Mode), warning_suffix);

    ENUM_ORDER_TYPE ot;
    if (sets.EntryType == Pending)
    {
        // Sell
        if (sets.TradeDirection == Short)
        {
            // Stop
            if (sets.EntryLevel < Bid) ot = OP_SELLSTOP;
            // Limit
            else ot = OP_SELLLIMIT;
        }
        // Buy
        else
        {
            // Stop
            if (sets.EntryLevel > Ask) ot = OP_BUYSTOP;
            // Limit
            else ot = OP_BUYLIMIT;
        }
    }
    // Instant
    else
    {
        // Sell
        if (sets.TradeDirection == Short) ot = OP_SELL;
        // Buy
        else ot = OP_BUY;
    }

    double PositionSize = OutputPositionSize;
    
    if ((sets.SubtractPendingOrders) || (sets.SubtractPositions))
    {
        double existing_volume_buy = 0, existing_volume_sell = 0;
        CalculateOpenVolume(existing_volume_buy, existing_volume_sell);
        Print("Found existing buy volume = ", DoubleToString(existing_volume_buy, LotStep_digits));
        Print("Found existing sell volume = ", DoubleToString(existing_volume_sell, LotStep_digits));
        if ((ot == OP_BUY) || (ot == OP_BUYLIMIT) || (ot == OP_BUYSTOP)) PositionSize -= existing_volume_buy;
        else PositionSize -= existing_volume_sell;
        Print("Adjusted position size = ", DoubleToString(PositionSize, LotStep_digits));
        if (PositionSize <= 0)
        {
            Alert("Adjusted position size is less or equal to zero. Not executing any trade.");
            return;
        }
        if (PositionSize != OutputPositionSize) // If changed, recalculate the array of position sizes.
        {
            PositionSizeToArray(PositionSize); // Re-fills ArrayPositionSize[].
        }
    }

    if ((sets.MaxPositionSizeTotal > 0) || (sets.MaxPositionSizePerSymbol > 0))
    {
        int total = OrdersTotal();
        double volume = 0, volume_persymbol = 0;
        for (int i = 0; i < total; i++)
        {
            if (!OrderSelect(i, SELECT_BY_POS)) continue;
            if ((sets.MagicNumber != 0) && (OrderMagicNumber() != sets.MagicNumber)) continue;
            if (OrderSymbol() == Symbol()) volume_persymbol += OrderLots();
            volume += OrderLots();
        }
        if ((volume + PositionSize > sets.MaxPositionSizeTotal) && (sets.MaxPositionSizeTotal > 0))
        {
            Alert("Not taking a trade - current total volume (", DoubleToString(volume, LotStep_digits), ") + new position volume (", DoubleToString(PositionSize, LotStep_digits), ") >= maximum total volume allowed (", DoubleToString(sets.MaxPositionSizeTotal, LotStep_digits), ").");
            return;
        }
        if ((volume_persymbol + PositionSize > sets.MaxPositionSizePerSymbol) && (sets.MaxPositionSizePerSymbol > 0))
        {
            Alert("Not taking a trade - current volume per symbol (", DoubleToString(volume_persymbol, LotStep_digits), ") + new position volume (", DoubleToString(PositionSize, LotStep_digits), ") >= maximum volume per symbol allowed (", DoubleToString(sets.MaxPositionSizePerSymbol, LotStep_digits), ").");
            return;
        }
    }

    datetime expiry = 0;
    if ((sets.EntryType == Pending) && (sets.ExpiryMinutes > 0))
    {
        expiry = TimeCurrent() + sets.ExpiryMinutes * 60;
    }

    if (sets.AskForConfirmation)
    {
        // Evoke confirmation modal window.
        string caption = "Position Sizer on " + Symbol() + " @ " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()), 7) + ": Execute the trade?";
        string message;
        string order_type_text = "";
        string currency = AccountInfoString(ACCOUNT_CURRENCY);
        switch(ot)
        {
        case OP_BUY:
            order_type_text = "Buy";
            break;
        case OP_BUYSTOP:
            order_type_text = "Buy Stop";
            break;
        case OP_BUYLIMIT:
            order_type_text = "Buy Limit";
            break;
        case OP_SELL:
            order_type_text = "Sell";
            break;
        case OP_SELLSTOP:
            order_type_text = "Sell Stop";
            break;
        case OP_SELLLIMIT:
            order_type_text = "Sell Limit";
            break;
        default:
            break;
        }

        message = "Order: " + order_type_text + "\n";
        message += "Size: " + DoubleToString(PositionSize, LotStep_digits);
        if (sets.TakeProfitsNumber > 1) message += " (multiple)";
        message += "\n";
        message += EnumToString(sets.AccountButton);
        message += ": " + FormatDouble(DoubleToString(AccSize, 2)) + " " + account_currency + "\n";
        message += "Risk: " + FormatDouble(DoubleToString(OutputRiskMoney)) + " " + account_currency + "\n";
        if (PositionMargin != 0) message += "Margin: " + FormatDouble(DoubleToString(PositionMargin, 2)) + " " + account_currency + "\n";
        message += "Entry: " + DoubleToString(sets.EntryLevel, _Digits) + "\n";
        if (!sets.DoNotApplyStopLoss) message += "Stop-loss: " + DoubleToString(sets.StopLossLevel, _Digits) + "\n";
        if ((sets.TakeProfitLevel > 0) && (!sets.DoNotApplyTakeProfit))
        {
            message += "Take-profit: " + DoubleToString(sets.TakeProfitLevel, _Digits);
            if (sets.TakeProfitsNumber > 1) message += " (multiple)";
            message += "\n";
        }
        if (expiry > 0) message += "Expiry: " + TimeToString(expiry, TIME_DATE|TIME_MINUTES|TIME_SECONDS);

        int ret = MessageBox(message, caption, MB_OKCANCEL | MB_ICONWARNING);
        if (ret == IDCANCEL)
        {
            Print("Trade canceled.");
            return;
        }
    }

    if (sets.DoNotApplyStopLoss)
    {
        Print("'Do not apply stop-loss' checkbox is ticked.");
    }
    if (sets.DoNotApplyTakeProfit)
    {
        Print("'Do not apply take-profit' checkbox is ticked.");
    }

    // Use ArrayPositionSize that has already been calculated in CalculateRiskAndPositionSize().
    // Check if they are OK.
    for (int j = sets.TakeProfitsNumber - 1; j >= 0; j--)
    {
        if (ArrayPositionSize[j] < MinLot)
        {
            Print("Position size ", ArrayPositionSize[j], " < broker's minimum position size. Not executing the trade.");
            ArrayPositionSize[j] = 0;
            continue;
        }
        else if ((ArrayPositionSize[j] > MaxLot) && (!SurpassBrokerMaxPositionSize))
        {
            Print("Position size ", ArrayPositionSize[j], " > broker's maximum position size. Reducing it.");
            ArrayPositionSize[j] = MaxLot;
        }
    }

    bool isOrderPlacementFailing = false; // Track if any of the order-operations fail.
    bool AtLeastOneOrderExecuted = false; // Track if at least one order got executed. Required for cases when some of the multiple TP orders have volume < minimum volume and don't get executed.

    // Will be used if MarketModeApplySLTPAfterAllTradesExecuted == true. 
    int array_of_tickets[];
    double array_of_sl[], array_of_tp[];
    ENUM_ORDER_TYPE array_of_ot[];
    int array_cnt = 0;
    
    // Going through a cycle to execute multiple TP trades.
    for (int j = 0; j < sets.TakeProfitsNumber; j++)
    {
        if (ArrayPositionSize[j] == 0) continue; // Calculated PS < broker's minimum.
        double order_sl = sets.StopLossLevel;
        double sl = order_sl;
        double order_tp = NormalizeDouble(TP[j], _Digits);
        double tp = order_tp;
        double position_size = NormalizeDouble(ArrayPositionSize[j], LotStep_digits);

        // Market execution mode - preparation.
        if ((Execution_Mode == SYMBOL_TRADE_EXECUTION_MARKET) && (sets.EntryType == Instant) && (!IgnoreMarketExecutionMode))
        {
            // No SL/TP allowed on instant orders.
            order_sl = 0;
            order_tp = 0;
        }
        if (sets.DoNotApplyStopLoss)
        {
            sl = 0;
            order_sl = 0;
        }
        if (sets.DoNotApplyTakeProfit)
        {
            tp = 0;
            order_tp = 0;
        }

        if ((order_tp != 0) && (((order_tp <= sets.EntryLevel) && ((ot == OP_BUY) || (ot == OP_BUYLIMIT) || (ot == OP_BUYSTOP))) || ((order_tp >= sets.EntryLevel) && ((ot == OP_SELL) || (ot == OP_SELLLIMIT) || (ot == OP_SELLSTOP))))) order_tp = 0; // Do not apply TP if it is invald. SL will still be applied.

        // Cycle for splitting up trade/subtrade into more subtrades starts here.
        while (position_size > 0)
        {
            double sub_position_size;
            if (position_size > MaxLot)
            {
                sub_position_size = MaxLot;
                position_size = NormalizeDouble(position_size - MaxLot, LotStep_digits);
            }
            else
            {
                sub_position_size = position_size;
                position_size = 0; // End the cycle;
            }
            int ticket = OrderSend(Symbol(), ot, sub_position_size, sets.EntryLevel, sets.MaxSlippage, order_sl, order_tp, Commentary, sets.MagicNumber, expiry);
            if (ticket == -1)
            {
                int error = GetLastError();
                Print("Execution failed. Error: ", IntegerToString(error), " - ", ErrorDescription(error), ".");
                isOrderPlacementFailing = true;
            }
            else
            {
                if (sets.TakeProfitsNumber == 1) Print("Order executed. Ticket: ", ticket, ".");
                else Print("Order #", j, " executed. Ticket: ", ticket, ".");
                AtLeastOneOrderExecuted = true;
            }
            if (!sets.DoNotApplyTakeProfit) tp = TP[j];
            // Market execution mode - applying SL/TP.
            if ((Execution_Mode == SYMBOL_TRADE_EXECUTION_MARKET) && (sets.EntryType == Instant) && (!IgnoreMarketExecutionMode) && (ticket != -1) && ((sl != 0) || (tp != 0)))
            {
                if (MarketModeApplySLTPAfterAllTradesExecuted) // Finish opening all trades, then apply all SLs and TPs.
                {
                    array_cnt++;
                    ArrayResize(array_of_tickets, array_cnt);
                    ArrayResize(array_of_sl, array_cnt);
                    ArrayResize(array_of_tp, array_cnt);
                    ArrayResize(array_of_ot, array_cnt);
                    array_of_tickets[array_cnt - 1] = ticket;
                    array_of_sl[array_cnt - 1] = sl;
                    array_of_tp[array_cnt - 1] = tp;
                    array_of_ot[array_cnt - 1] = ot;
                }
                else
                {
                    if (!ApplySLTPToOrder(ticket, sl, tp, ot))
                    {
                        isOrderPlacementFailing = true;
                        break;
                    }
                }
            }
        } // Cycle for splitting up trade/subtrade into more subtrades ends here.
    }
    
    // Run position adjustment if necessary.
    for (int j = 0; j < array_cnt; j++)
    {
        if (!ApplySLTPToOrder(array_of_tickets[j], array_of_sl[j], array_of_tp[j], array_of_ot[j]))
        {
            isOrderPlacementFailing = true;
        }
    }
    
    if (!DisableTradingSounds) PlaySound((isOrderPlacementFailing) || (!AtLeastOneOrderExecuted) ? "timeout.wav" : "ok.wav");
}

// Applies SL/TP to a single order (used in the Market execution mode).
// Returns false in case of a failure, true - in case of a success.
bool ApplySLTPToOrder(int ticket, double sl, double tp, ENUM_ORDER_TYPE ot)
{
    if (!OrderSelect(ticket, SELECT_BY_TICKET))
    {
        Print("Failed to find the order to apply SL/TP.");
        return false;
    }
    for (int i = 0; i < 10; i++)
    {
        if ((tp != 0) && (((tp <= OrderOpenPrice()) && (ot == OP_BUY)) || ((tp >= OrderOpenPrice()) && (ot == OP_SELL)))) tp = 0; // Do not apply TP if it is invald. SL will still be applied.
        bool result = OrderModify(ticket, OrderOpenPrice(), sl, tp, OrderExpiration());
        if (result)
        {
            return true;
        }
        else
        {
            Print("Error modifying the order: ", GetLastError());
        }
    }
    return false;
}

// Calculate volume of open positions and/or pending orders.
// Counts volumes separately for buy and sell trades and writes them into parameterss.
void CalculateOpenVolume(double &volume_buy, double &volume_sell)
{
    int total = OrdersTotal();
    for (int i = 0; i < total; i++)
    {
        // Select an order.
        if (!OrderSelect(i, SELECT_BY_POS)) continue;
        // Skip orders with a different trading instrument.
        if (OrderSymbol() != _Symbol) continue;
        // If magic number is given via PS panel and order's magic number is different - skip.
        if ((sets.MagicNumber != 0) && (OrderMagicNumber() != sets.MagicNumber)) continue;

        if (sets.SubtractPositions)
        {
            // Buy orders
            if (OrderType() == ORDER_TYPE_BUY) volume_buy += OrderLots();
            // Sell orders
            else if (OrderType() == ORDER_TYPE_SELL) volume_sell += OrderLots();
        }
        if (sets.SubtractPendingOrders)
        {
            // Buy orders
            if ((OrderType() == ORDER_TYPE_BUY_LIMIT) || (OrderType() == ORDER_TYPE_BUY_STOP)) volume_buy += OrderLots();
            // Sell orders
            else if ((OrderType() == ORDER_TYPE_SELL_LIMIT) || (OrderType() == ORDER_TYPE_SELL_STOP)) volume_sell += OrderLots();
        }
    }
}

// Does trailing based on the Magic number and symbol.
void DoTrailingStop()
{
    if ((!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) || (!TerminalInfoInteger(TERMINAL_CONNECTED)) || (!MQLInfoInteger(MQL_TRADE_ALLOWED))) return;

    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (!OrderSelect(i, SELECT_BY_POS)) Print("OrderSelect failed " + ErrorDescription(GetLastError()) + ".");
        else if (SymbolInfoInteger(OrderSymbol(), SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) continue;
        else
        {
            if ((OrderSymbol() != Symbol()) || (OrderMagicNumber() != sets.MagicNumber)) continue;
            if (OrderType() == OP_BUY)
            {
                double SL = NormalizeDouble(Bid - sets.TrailingStopPoints * _Point, _Digits);
                if (SL > OrderStopLoss())
                {
                    if (!OrderModify(OrderTicket(), OrderOpenPrice(), SL, OrderTakeProfit(), OrderExpiration()))
                        Print("OrderModify Buy TSL failed " + ErrorDescription(GetLastError()) + ".");
                    else
                        Print("Trailing stop was applied to position - " + Symbol() + " BUY-order #" + IntegerToString(OrderTicket()) + " Lotsize = " + DoubleToString(OrderLots(), LotStep_digits) + ", OpenPrice = " + DoubleToString(OrderOpenPrice(), _Digits) + ", Stop-Loss was moved from " + DoubleToString(OrderStopLoss(), _Digits) + " to " + DoubleToString(SL, _Digits) + ".");
                }
            }
            else if (OrderType() == OP_SELL)
            {
                double SL = NormalizeDouble(Ask + sets.TrailingStopPoints * _Point, _Digits);
                if ((SL < OrderStopLoss()) || (OrderStopLoss() == 0))
                {
                    if (!OrderModify(OrderTicket(), OrderOpenPrice(), SL, OrderTakeProfit(), OrderExpiration()))
                        Print("OrderModify Sell TSL failed " + ErrorDescription(GetLastError()) + ".");
                    else
                        Print("Trailing stop was applied to position - " + Symbol() + " SELL-order #" + IntegerToString(OrderTicket()) + " Lotsize = " + DoubleToString(OrderLots(), LotStep_digits) + ", OpenPrice = " + DoubleToString(OrderOpenPrice(), _Digits) + ", Stop-Loss was moved from " + DoubleToString(OrderStopLoss(), _Digits) + " to " + DoubleToString(SL, _Digits) + ".");
                }
            }
        }
    }
}

// Sets SL to breakeven based on the Magic number and symbol.
void DoBreakEven()
{
    if (!TerminalInfoInteger(TERMINAL_CONNECTED)) return;
    
    // Delete old BE lines if necessary.
    if (be_line_color != clrNONE)
    {
        int obj_total = ObjectsTotal(ChartID(), -1, OBJ_HLINE);
        for (int i = obj_total - 1; i >= 0; i--)
        {
            string obj_name = ObjectName(ChartID(), i, -1, OBJ_HLINE);
            if (StringFind(obj_name, ObjectPrefix + "BE") == -1) continue; // Skip all other horizontal lines.
            int ticket = (int)StringToInteger(StringSubstr(obj_name, StringLen(ObjectPrefix + "BE")));
            if (!OrderSelect(ticket, SELECT_BY_TICKET)) // No longer exists.
            {
                ObjectDelete(ChartID(), obj_name); // Delete the line.
                if (ShowLineLabels) ObjectDelete(ChartID(), ObjectPrefix + "BEL" + IntegerToString(ticket)); // Delete the label.
            }
            else // Check if already triggered. Order selected.
            {
                double be_price = NormalizeDouble(StringToDouble(ObjectGetString(ChartID(), obj_name, OBJPROP_TOOLTIP)), _Digits);
                if (((OrderType() == OP_BUY) && (OrderStopLoss() >= be_price)) // Already triggered.
                 || ((OrderType() == OP_SELL) && (OrderStopLoss() <= be_price) && (OrderStopLoss() != 0)))
                {
                    ObjectDelete(ChartID(), obj_name); // Delete the line.
                    if (ShowLineLabels) ObjectDelete(ChartID(), ObjectPrefix + "BEL" + IntegerToString(ticket)); // Delete the label.
                }
            }
        }
    }
    
    if (sets.BreakEvenPoints <= 0) return;
    
    if ((!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) || (!MQLInfoInteger(MQL_TRADE_ALLOWED))) return;

    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (!OrderSelect(i, SELECT_BY_POS)) Print("OrderSelect failed " + ErrorDescription(GetLastError()) + ".");
        else if (SymbolInfoInteger(OrderSymbol(), SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) continue;
        else
        {
            if ((OrderSymbol() != Symbol()) || (OrderMagicNumber() != sets.MagicNumber)) continue;

            // Based on the commission if UseCommissionToSetTPDistance is set to true.
            double extra_be_distance = 0;
            if ((UseCommissionToSetTPDistance) && (sets.CommissionPerLot != 0))
            {
                // Calculate real commission in currency units.
                double commission = CalculateCommission();

                // Extra BE Distance = Commission Size / Point_value.
                // Commission Size = Commission * 2.
                // Extra BE Distance = Commission * 2 / Point_value.
                if ((UnitCost_reward != 0) && (TickSize != 0))
                    extra_be_distance = commission * 2 / (UnitCost_reward / TickSize);
            }

            if (OrderType() == OP_BUY)
            {
                double BE_threshold = NormalizeDouble(OrderOpenPrice() + sets.BreakEvenPoints * _Point, _Digits);
                double BE_price = NormalizeDouble(OrderOpenPrice() + extra_be_distance, _Digits);
                if ((be_line_color != clrNONE) && (BE_price > OrderStopLoss())) DrawBELine(OrderTicket(), BE_threshold, BE_price); // Only draw if not triggered yet.
                if ((Bid >= BE_threshold) && (Bid >= BE_price) && (BE_price > OrderStopLoss())) // Only move to BE if the price reached the necessary threshold, the price is above the calculated BE price, and the current stop-loss is lower.
                {
                    double prev_sl = OrderStopLoss(); // Remember old SL for reporting.
                    // Write Open price to the SL field.
                    if (!OrderModify(OrderTicket(), OrderOpenPrice(), BE_price, OrderTakeProfit(), OrderExpiration()))
                        Print("OrderModify Buy BE failed " + ErrorDescription(GetLastError()) + ".");
                    else
                        Print("Breakeven was applied to position - " + Symbol() + " BUY-order #" + IntegerToString(OrderTicket()) + " Lotsize = " + DoubleToString(OrderLots(), LotStep_digits) + ", OpenPrice = " + DoubleToString(OrderOpenPrice(), _Digits) + ", Stop-Loss was moved from " + DoubleToString(prev_sl, _Digits) + ".");
                }
            }
            else if (OrderType() == OP_SELL)
            {
                double BE_threshold = NormalizeDouble(OrderOpenPrice() - sets.BreakEvenPoints * _Point, _Digits);
                double BE_price = NormalizeDouble(OrderOpenPrice() - extra_be_distance, _Digits);
                if ((be_line_color != clrNONE) && ((BE_price < OrderStopLoss()) || (OrderStopLoss() == 0))) DrawBELine(OrderTicket(), BE_threshold, BE_price);
                if ((Ask <= BE_threshold) && (Ask <= BE_price) && ((BE_price < OrderStopLoss()) || (OrderStopLoss() == 0))) // Only move to BE if the price reached the necessary threshold, the price below the calculated BE price, and the current stop-loss is higher (or zero).
                {
                    double prev_sl = OrderStopLoss(); // Remember old SL for reporting.
                    // Write Open price to the SL field.
                    if (!OrderModify(OrderTicket(), OrderOpenPrice(), BE_price, OrderTakeProfit(), OrderExpiration()))
                        Print("OrderModify Sell BE failed " + ErrorDescription(GetLastError()) + ".");
                    else
                        Print("Breakeven was applied to position - " + Symbol() + " SELL-order #" + IntegerToString(OrderTicket()) + " Lotsize = " + DoubleToString(OrderLots(), LotStep_digits) + ", OpenPrice = " + DoubleToString(OrderOpenPrice(), _Digits) + ", Stop-Loss was moved from " + DoubleToString(prev_sl, _Digits) + ".");
                }
            }
        }
    }
}

void DrawBELine(int ticket, double be_threshold, double be_price)
{
    string obj_name = ObjectPrefix + "BE" + IntegerToString(ticket); // Line.
    ObjectCreate(ChartID(), obj_name, OBJ_HLINE, 0, TimeCurrent(), be_threshold);
    ObjectSetDouble(ChartID(), obj_name, OBJPROP_PRICE, be_threshold);
    ObjectSetInteger(ChartID(), obj_name, OBJPROP_STYLE, be_line_style);
    ObjectSetInteger(ChartID(), obj_name, OBJPROP_COLOR, be_line_color);
    ObjectSetInteger(ChartID(), obj_name, OBJPROP_WIDTH, be_line_width);
    ObjectSetInteger(ChartID(), obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(ChartID(), obj_name, OBJPROP_BACK, true);
    ObjectSetString(ChartID(), obj_name, OBJPROP_TOOLTIP, DoubleToString(be_price, _Digits)); // Store BE price in the tooltip.

    if (sets.ShowLines) ObjectSetInteger(ChartID(), obj_name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    else ObjectSetInteger(ChartID(), obj_name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);

    if (ShowLineLabels)
    {
        obj_name = ObjectPrefix + "BEL" + IntegerToString(ticket); // Label.
        ObjectCreate(ChartID(), obj_name, OBJ_LABEL, 0, 0, 0);
        if (sets.ShowLines) ObjectSetInteger(ChartID(), obj_name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        else ObjectSetInteger(ChartID(), obj_name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(ChartID(), obj_name, OBJPROP_COLOR, clrNONE);
        ObjectSetInteger(ChartID(), obj_name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(ChartID(), obj_name, OBJPROP_HIDDEN, false);
        ObjectSetInteger(ChartID(), obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(ChartID(), obj_name, OBJPROP_BACK, DrawTextAsBackground);
        ObjectSetString(ChartID(), obj_name, OBJPROP_TOOLTIP, "");
        string text = "BE for ";
        if (OrderType() == OP_BUY) text += "Buy";
        else if (OrderType() == OP_SELL) text += "Sell";
        text += " #" + IntegerToString(ticket);
        DrawLineLabel(obj_name, text, be_threshold, be_line_color, false, -6);
    }
}
//+------------------------------------------------------------------+