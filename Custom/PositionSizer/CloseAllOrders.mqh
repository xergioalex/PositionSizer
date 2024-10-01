//-- Include
#include <stdlib.mqh>

enum ENUM_CLOSE_ORDER_TYPES {
    ALL_ORDERS_PENDING_AND_MARKET = 1, // ALL ORDERS (PENDING AND MARKET)
    ONLY_PENDING_ORDERS = 2,   // ONLY PENDING ORDERS
    ONLY_MARKET_ORDERS = 3   // ONLY MARKET ORDERS
};

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+

void CloseAllOrders(bool forceCloseAllOrders = false) {
  Print("#######################################");
  Print("##### • START CLOSE ALL ORDERS • #####");
  Print("");
  
  CloseAllOrdersStrategy(forceCloseAllOrders);

  Print("");
  Print("##### • END CLOSE ALL ORDERS • #####");
  Print("#####################################");
}


void CloseAllOrdersStrategy(bool forceCloseAllOrders = false) {
    // Check if there are any open orders
    int ordersTotal = OrdersTotal();
    int marketOrdersTotal = 0;
    int pendingOrdersTotal = 0;
    Print("Total orders: ", ordersTotal);
    if (ordersTotal == 0) {
        Print("No orders found to close");
        return;
    }

    int errorsCount = 0;
    // The loop starts from the last, otherwise it could skip orders.
    for (int i = ordersTotal - 1; i >= 0; i--) {
        // Select the order by its position in the list of open orders
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            Print("Error selecting order with ticket: ", OrderTicket(), " - ", ErrorDescription(GetLastError()));
            errorsCount++;
            continue;
        }

        // Get the type of the selected order
        int orderType = OrderType();

        if (orderType == OP_BUY || orderType == OP_SELL) {
            marketOrdersTotal++;
        }
        if (orderType == OP_BUYLIMIT || orderType == OP_SELLLIMIT || orderType == OP_BUYSTOP || orderType == OP_SELLSTOP) {
            pendingOrdersTotal++;
        }

        if (!forceCloseAllOrders) {
            if ((CloseOnlyCurrentSymbol) && (OrderSymbol() != Symbol())) continue;
            if ((CloseOrderTypeFilter == ONLY_PENDING_ORDERS) && (orderType == OP_BUY || orderType == OP_SELL)) continue;
            if ((CloseOrderTypeFilter == ONLY_MARKET_ORDERS) && (orderType != OP_BUY || orderType != OP_SELL)) continue;
        }

        // Delete pending orders (buy limit, sell limit, buy stop, sell stop)
        if (orderType == OP_BUYLIMIT || orderType == OP_SELLLIMIT || orderType == OP_BUYSTOP || orderType == OP_SELLSTOP) {
            if (!OrderDelete(OrderTicket(), clrNONE)) {
                Print("Error deleting order with ticket: ", OrderTicket(), " - ", ErrorDescription(GetLastError()));
                errorsCount++;
                continue;
            }
        }

        if (orderType == OP_BUY || orderType == OP_SELL) {
            // Close market orders (buy or sell)

            // Bid and Ask price for the order's symbol.
            double BidPrice = MarketInfo(OrderSymbol(), MODE_BID);
            double AskPrice = MarketInfo(OrderSymbol(), MODE_ASK);

            if (orderType == OP_BUY) {
                if (OrderClose(OrderTicket(), OrderLots(), BidPrice, 0, clrNONE)) {
                    Print("Closing BUY order with ticket: ", OrderTicket(), " and ", OrderLots(), "lots");
                } else {
                    Print("Error: ", ErrorDescription(GetLastError()));
                    errorsCount++;
                    continue;
                }
            }

            if (orderType == OP_SELL) {
                if (OrderClose(OrderTicket(), OrderLots(), AskPrice, 0, clrNONE)) {
                    Print("Closing SELL order with ticket: ", OrderTicket(), " and ", OrderLots(), "lots");
                } else {
                    Print("Error: ", ErrorDescription(GetLastError()));
                    errorsCount++;
                    continue;
                }
            }
        }
    }

    Print("Total market orders: ", marketOrdersTotal);
    Print("Total pending orders: ", pendingOrdersTotal);

    if (errorsCount == 0) {
        Print("All pending orders have been closed");
    } else {
        Print("Some orders were not closed due to errors: ", errorsCount);
    }
}
//+------------------------------------------------------------------+
