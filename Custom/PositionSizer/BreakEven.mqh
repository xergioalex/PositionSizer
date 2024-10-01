#include <stdlib.mqh>;

enum ENUM_ORDER_TYPES {
    ALL_ORDERS = 1, // ALL ORDERS
    ONLY_BUY = 2,   // BUY ONLY
    ONLY_SELL = 3   // SELL ONLY
};

// Start program to start the function.
void BreakEven() {
  Print("#######################################");
  Print("##### • START BREAK EVEN SCRIPT • #####");
  Print("");
  
  StartBreakEvenStrategy();

  Print("");
  Print("##### • END BREAK EVEN SCRIPT • #####");
  Print("#####################################");
}


void StartBreakEvenStrategy() {
  // Check if terminal is connected
  if (!TerminalInfoInteger(TERMINAL_CONNECTED)) {
    Print("Not connected to the trading server. Exiting.");
    return;
  }

  // Check if trading is allowed
  if ((!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) || (!MQLInfoInteger(MQL_TRADE_ALLOWED))) {
    Print("Autotrading is disable. Please enable. Exiting.");
    return;
  }

  // Get total orders
  int ordersTotal = OrdersTotal();
  int marketOrdersTotal = 0;
  int marketOrdersModifiedTotal = 0;
  Print("Total orders: ", ordersTotal);


  // If no orders found, exit
  if (ordersTotal == 0) {
    Print("No orders found.");
    return;
  }

  double profitDollarsToSet = 10;
  // Loop through all orders
  for (int i = 0; i < ordersTotal; i++) {
    // Select order by position
    if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
      Print("ERROR - Unable to select the order: ", GetLastError());
      continue;
    }

    // Get order type
    int orderType = OrderType();
    if (orderType == OP_BUY || orderType == OP_SELL) {
        marketOrdersTotal++;
        // Apply break even strategy to the order
        if (ApplyOrderBreakEven(orderType)) {
            marketOrdersModifiedTotal++;
        }
    }
    
  }

  Print("Total market orders: ", marketOrdersTotal);
  Print("Total market orders modified: ", marketOrdersModifiedTotal);
}


double GetPipValueMultiplier() {
  // Return pip value multiplier based on the number of digits
  if (Digits == 5 || Digits == 3 || Digits == 2) {
    return MathPow(10, Digits);
  } else {
    return 0;
  }
}

string GetOrderTypeStr(int orderType) {
  // Return order type as string
  switch(orderType) {
    case OP_BUY:
      return "Buy";
    case OP_SELL:
      return "Sell";
    case OP_BUYLIMIT:
      return "Buy Limit";
    case OP_SELLLIMIT:
      return "Sell Limit";
    case OP_BUYSTOP:
      return "Buy Stop";
    case OP_SELLSTOP:
      return "Sell Stop";
    default:
      return "Unknown";
  }
}

double ShouldApplyBreakEvenToTheOrder(double riskDollars, double profitDollars, double currentProfitDollars) {
  // Verify if we can calculate the break even
  if ((!riskDollars > 0 && profitDollars > 0 && currentProfitDollars != 0)) {
    return false;
  } 

  // If the profit is less than half of the risk, we don't apply the break even
  if (profitDollars > 0 && profitDollars < (riskDollars / 4)) {
    return false;
  }

  // Depending on the current profit, we will calculate the break even in dollars
  if (currentProfitDollars > 0) {
    double positiveProfitPercentage = (currentProfitDollars * 100) / profitDollars;
    Print("Positive Profit Percentage: ", positiveProfitPercentage);
    if (MathAbs(positiveProfitPercentage) > PercentageOfPositiveProfitToBreakEven) {
      return true;
    }
  } else {
    double negativeProfitPercentage = (currentProfitDollars * 100) / riskDollars;
    Print("Negative Profit Percentage: ", negativeProfitPercentage);
    if (MathAbs(negativeProfitPercentage) > PercentageOfNegativeProfitToBreakEven) {
      return true;
    }
  }
  return false;
}

double CalcBreakEvenDollars(double orderCommission, double orderSwap) {
  // Calculate break even in dollars
  double breakEvenDollars = (orderCommission + (orderCommission * 0.10)) + orderSwap;
  if (breakEvenDollars > 0) {
    breakEvenDollars = orderCommission;
  }
  return MathAbs(breakEvenDollars);
}

bool ApplyOrderBreakEven(int orderType) {
  // Get order details
  int orderTicket = OrderTicket();
  string orderSymbol = OrderSymbol();
  double orderOpenPrice = OrderOpenPrice();
  double orderLotsSize = OrderLots();
  double orderStopLoss = OrderStopLoss();
  double orderTakeProfit = OrderTakeProfit();
  datetime orderExpiration = OrderExpiration();
  double orderCommission = OrderCommission();
  double orderSwap = OrderSwap();
  int orderMagicNumber = OrderMagicNumber();
  string orderComment = OrderComment();
  double currentProfitDollars = OrderProfit();

  // Check if the order matches the filter and if not, skip the order and move to the next one.
  if (!(orderType == OP_BUY || orderType == OP_SELL)) return false;
  if ((OrderTypeFilter == ONLY_SELL) && (orderType == OP_BUY)) return false;
  if ((OrderTypeFilter == ONLY_BUY)  && (orderType == OP_SELL)) return false;
  if ((OnlyCurrentSymbol) && (orderSymbol != Symbol())) return false;
  if ((OnlyMagicNumber) && (orderMagicNumber != MagicNumber)) return false;
  if ((OnlyWithComment) && (StringCompare(orderComment, MatchingComment) != 0)) return false;

  // Verify if the order Break Even was already applied
  if (orderType == OP_BUY) {
    if (orderStopLoss > orderOpenPrice) {
      return false;
    }
  } else if (orderType == OP_SELL) {
    if (orderOpenPrice > orderStopLoss) {
      return false;
    }
  }
  
  // Calculate risk and profit in dollars
  double pipValue = MarketInfo(orderSymbol, MODE_TICKVALUE);
  double pipValueMultiplier = GetPipValueMultiplier();

  // If pip value multiplier is 0, continue to the next order
  if (pipValueMultiplier == 0) {
    return false;
  }
  double profitDollars = 0.0;  
  double riskDollars = 0.0; 
  double lotSizePipValue = (orderLotsSize * pipValue);
  
  if (orderType == OP_BUY) {
    // Calculate risk and profit in pips and dollars
    double riskPipDiff = (orderOpenPrice - orderStopLoss);
    double profitPipDiff = (orderTakeProfit - orderOpenPrice);
    riskDollars = (riskPipDiff * lotSizePipValue) * pipValueMultiplier;
    profitDollars = (profitPipDiff * lotSizePipValue) * pipValueMultiplier;

    // Verify if we should apply break even to the order
    if (!ShouldApplyBreakEvenToTheOrder(riskDollars, profitDollars, currentProfitDollars)) {
      Print("Should NOT apply break even to the order");
      return false;
    }

    // Calculate break even in dollars
    double breakEvenDollars = CalcBreakEvenDollars(orderCommission, orderSwap);
    double profitPips = breakEvenDollars / lotSizePipValue;
    if (currentProfitDollars > 0) {
      orderStopLoss = orderOpenPrice + (profitPips * Point);
    } else {
      orderTakeProfit = orderOpenPrice + (profitPips * Point);
    }
  } else if (orderType == OP_SELL) {
    // Calculate risk and profit in pips and dollars
    double riskPipDiff = (orderStopLoss - orderOpenPrice);
    double profitPipDiff = (orderOpenPrice - orderTakeProfit);
    riskDollars = (riskPipDiff * lotSizePipValue) * pipValueMultiplier;
    profitDollars = (profitPipDiff * lotSizePipValue) * pipValueMultiplier;

    // Verify if we should apply break even to the order
    if (!ShouldApplyBreakEvenToTheOrder(riskDollars, profitDollars, currentProfitDollars)) {
      Print("Should NOT apply break even to the order");
      return false;
    }
    
    // Calculate break even in dollars
    double breakEvenDollars = CalcBreakEvenDollars(orderCommission, orderSwap);
    double profitPips = breakEvenDollars / lotSizePipValue;
    if (currentProfitDollars > 0) {
      orderStopLoss = orderOpenPrice - (profitPips * Point);
    } else {
      orderTakeProfit = orderOpenPrice - (profitPips * Point);
    }
  }

  // Modify order
  if (!OrderModify(orderTicket, orderOpenPrice, orderStopLoss, orderTakeProfit, orderExpiration, clrNONE)) {
    Print("Error modifying order: ", ErrorDescription(GetLastError()));
    return false;
  }
  
  // Print order details
  string orderTypeStr = GetOrderTypeStr(orderType);
  Print("Order #", orderTicket, ": Symbol = ", orderSymbol, ", Type = ", orderTypeStr, ", Price = ", orderOpenPrice, ", Lot Size = ", orderLotsSize, ", Stop Loss = ", orderStopLoss, ", Take Profit = ", orderTakeProfit, ", Risk ($) = ", riskDollars, ", Profit ($) = ", profitDollars);
  return true;
}