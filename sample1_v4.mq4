//+------------------------------------------------------------------+
//|                                                   sample1_v4.mq4 |
//|                        Copyright 2021, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

enum SMA_Period {
    SMA20 = 20,
    SMA50 = 50
};

input SMA_Period    inSlowMAPeriod  = SMA20;        // Dieu kien vao lenh
extern double       inVolume        = 0.01;         // Khoi luong
input int           inStochK        = 5;            // Stochastic K Period, default 5
input int           inStochD        = 3;            // Stochastic D Period, default 3
input int           inStochSlowing  = 3;            // Stochastic Slowing, default 3
ENUM_MA_METHOD      ma_method       = MODE_SMA;     // Moving Average Type
ENUM_STO_PRICE      sto_method      = STO_LOWHIGH;  // Calculation is based on Low/High prices
ENUM_APPLIED_PRICE  maAppliedPrice  = PRICE_CLOSE;
int                 fastMAPeriod    = 9;

// these two variables for extend only, not required
bool                isBuyAllowed    = true;
bool                isSellAllowed   = true;

bool                isStochBuyAllowed   = false;
bool                isStochSellAllowed  = false;

bool                isSMABuyAllowed     = false;
bool                isSMASellAllowed    = false;

int                 retryNumber     = 10;           // Number of attempt

// Not use
double              kTakeProfit     = 100;          // Take profit in pips

int                 kSlippage       = 0;            // No information, keep 0
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
//---
//---
    return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
//---
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    checkOrdersAllowed();
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void checkOrdersAllowed() {
    for(int i = 0; i < OrdersTotal(); i++) {
        if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) == false) {
            Print("ERROR - Failed to select the order, error: ", GetLastError());
            continue;
        }
        if((OrderSymbol()== _Symbol) && (OrderType() == OP_BUY)) isBuyAllowed = false;
        if((OrderSymbol()== _Symbol) && (OrderType() == OP_SELL)) isSellAllowed = false;
    }
    if (isBuyAllowed || isSellAllowed) {
        kiemtraDieuKien();
    }
}

bool checkStochCross(int inShift, bool& outBuyAllowed, bool& outSellAllowed) {
    double prev_sto_m = iStochastic(Symbol(),0,inStochK,inStochD,inStochSlowing,ma_method,sto_method,MODE_MAIN,inShift+1);      // K: green line
    double prev_sto_s = iStochastic(Symbol(),0,inStochK,inStochD,inStochSlowing,ma_method,sto_method,MODE_SIGNAL,inShift+1);    // D: red line

    double curr_sto_m = iStochastic(Symbol(),0,inStochK,inStochD,inStochSlowing,ma_method,sto_method,MODE_MAIN,inShift);    // K: green line
    double curr_sto_s = iStochastic(Symbol(),0,inStochK,inStochD,inStochSlowing,ma_method,sto_method,MODE_SIGNAL,inShift);  // D: red line

    outBuyAllowed = (prev_sto_m < prev_sto_s) && (curr_sto_m > curr_sto_s); // K cross upward D
    outSellAllowed = (prev_sto_m > prev_sto_s) &&  (curr_sto_m < curr_sto_s); // K cross downward
    return (outBuyAllowed || outSellAllowed);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void kiemtraDieuKien() {
    // reset conditions
    isStochBuyAllowed = false;
    isStochSellAllowed = false;
    isSMABuyAllowed = false;
    isSMASellAllowed = false;

    double ma9_1 = iMA(NULL, 0, 9, 0, fastMAPeriod, maAppliedPrice, 1);
    double ma9_2 = iMA(NULL, 0, 9, 0, fastMAPeriod, maAppliedPrice, 2);
    double lma1 = iMA(NULL, 0, inSlowMAPeriod, 0, ma_method, maAppliedPrice,1);
    double lma2 = iMA(NULL, 0, inSlowMAPeriod, 0, ma_method, maAppliedPrice, 2);
    isSMABuyAllowed = (ma9_2 < lma2) && (ma9_1 > lma1);     // SMA9 cross upward
    isSMASellAllowed = (ma9_2 > lma2) && (ma9_1 < lma1);    // SMA9 cross downward
    //Print("ma buy: ", isSMABuyAllowed, ", ma sell: ", isSMASellAllowed);
    if (isSMABuyAllowed || isSMASellAllowed) {
        for (int shift=2;shift<=4;shift++) {
            if (checkStochCross(shift,isStochBuyAllowed,isStochSellAllowed)) break;
        }
        //Print("sto buy: ", isStochBuyAllowed, ", sto sell: ", isStochSellAllowed);
        refine_volume();
        inVolume = NormalizeDouble(inVolume,Digits);
        // ORDER BUY
        if (isStochBuyAllowed && isSMABuyAllowed) {
            double stopLoss = findStoploss(true); // bottom of the previous ZigZag
            //stopLoss=Ask-zigzag_bottom*Point;
            bool isOrderPlaced = false;
            for(int i=0; i<retryNumber && !isOrderPlaced; i++) {
                int ticketNumber = OrderSend(_Symbol,OP_BUY,inVolume,Ask,kSlippage,0,0,"BUY",0,0,Green);
                if(ticketNumber > 0) {
                    for (int j=0; j<retryNumber && stopLoss>0; j++) {
                        if(OrderSelect(ticketNumber,SELECT_BY_TICKET) == false ) {
                            Print("ERROR - Failed to select the order - ", GetLastError());
                            Sleep(50);
                            continue;
                        } else {
                            if (OrderModify(OrderTicket(),OrderOpenPrice(),NormalizeDouble(stopLoss,Digits),OrderTakeProfit(),0,clrNONE)) {
                                isOrderPlaced = true;
                                break;
                            } else {
                                Print("ERROR - NEW - error modifying order, return error: ",GetLastError());
                            }
                        }
                    }
                } else Print("ERROR - NEW - error sending order, return error: ",GetLastError());
            }
        }
        // ORDER SELL
        if (isStochSellAllowed && isSMASellAllowed) {
            double stopLoss = findStoploss(false); // top of the previous ZigZag
            //stopLoss=Bid+zigzag_bottom*Point;
            bool isOrderPlaced = false;
            for(int i=0; i<retryNumber && !isOrderPlaced; i++) {
                int ticketNumber = OrderSend(_Symbol,OP_SELL,inVolume,Bid,kSlippage,0,0,"SELL",0,0,Green);
                if(ticketNumber > 0) {
                    for (int j=0; j<retryNumber && stopLoss>0; j++) {
                        if(OrderSelect(ticketNumber,SELECT_BY_TICKET) == false ) {
                            Print("ERROR - Failed to select the order - ", GetLastError());
                            Sleep(50);
                            continue;
                        } else {
                            if (OrderModify(OrderTicket(),OrderOpenPrice(),NormalizeDouble(stopLoss,Digits),OrderTakeProfit(),0,clrNONE)) {
                                isOrderPlaced = true;
                                break;
                            } else {
                                Print("ERROR - NEW - error modifying order, return error: ",GetLastError());
                            }
                        }
                    }
                } else Print("ERROR - NEW - error sending order, return error: ",GetLastError());
            }
        }
    }
    // TP: Co nen dong cua duoi MA9 => CLOSE BUY ORDERS
    // CLOSE SELL khi co nen mo cua tren MA9
    double ma9_closePrice = iMA(NULL, 0, 9, 0, ma_method, PRICE_CLOSE, 0);
    double ma9_openPrice = iMA(NULL, 0, 9, 0, ma_method, PRICE_OPEN, 0);
    for(int i = 0; i < OrdersTotal(); i++ ) {
        if( OrderSelect( i, SELECT_BY_POS, MODE_TRADES ) == false ) {
            Print("ERROR - Failed to select the order - ", GetLastError());
            continue;
        }
        // CLOSE BUY nếu có nến đóng cửa dưới ma9
        if(OrderSymbol()==_Symbol && OrderType()==OP_BUY && iClose(Symbol(),0,1)<ma9_closePrice) {
            for(int j=1; j<retryNumber; j++) {
                bool res=OrderClose(OrderTicket(),OrderLots(),OrderClosePrice(),kSlippage,Red);
                if(res) {
                    Print("TRADE - CLOSE - Order ", OrderTicket()," closed at price ",OrderClosePrice());
                    break;
                } else Print("ERROR - CLOSE - error closing order ", OrderTicket()," return error: ",GetLastError());
                Sleep(50);
            }
        }
        // Ngược lại CLOSE SELL nếu có nến mở cửa trên ma9
        if(OrderSymbol()==_Symbol && OrderType()==OP_SELL && iOpen(Symbol(),0,1)>ma9_openPrice) {
            for(int j=1; j<retryNumber; j++) {
                bool res=OrderClose(OrderTicket(),OrderLots(),OrderOpenPrice(),kSlippage,Red);
                if(res) {
                    Print("TRADE - CLOSE - Order ", OrderTicket()," opened at price ",OrderOpenPrice());
                    break;
                } else Print("ERROR - CLOSE - error closing order ", OrderTicket()," return error: ",GetLastError());
                Sleep(50);
            }
        }
    }
}

// ZigZag
double findStoploss(bool isBottom) {
    // ZigZag: mode is BufferIndex:
    // 0: double ExtZigzagBuffer[]
    // 1: double ExtHighBuffer[]
    // 2: double ExtLowBuffer[]
    //                                    mode,shift
    // iCustom(Symbol(),0,"ZigZag",12,5,3,0,i);
    int counted_bars=IndicatorCounted();
    int limit=0;
    limit = Bars-counted_bars;
    double ret = 0;
    for (int shift=0; shift<limit; shift++) {
        ret = iCustom(Symbol(),0,"ZigZag",12,5,3,0,shift);
        if (isBottom) {
            if(ret>0.1 && Low[shift]==ret) {
                break;
            }
        } else {
            if(ret>0.1 && High[shift]==ret) {
                break;
            }
        }

    }
    return ret;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void refine_volume() {
    /*
    int digit=0;
    double minLot = MarketInfo(inSym,MODE_MINLOT);
    if(minLot==0.01) digit=2;
    if(minLot==0.001) digit=3;
    if(minLot==0.1) digit=1;
    inVolume = NormalizeDouble(inVolume,digit);
    */
    if (inVolume < MarketInfo(_Symbol,MODE_MINLOT)) inVolume=MarketInfo(_Symbol,MODE_MINLOT);
    if (inVolume > MarketInfo(_Symbol,MODE_MAXLOT)) inVolume=MarketInfo(_Symbol,MODE_MAXLOT);
    //inVolume = NormalizeDouble(inVolume,2);
}
