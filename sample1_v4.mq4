//+------------------------------------------------------------------+
//|                                                   sample1_v4.mq4 |
//|                        Copyright 2021, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

enum SMACondition {
    SMA9_SMA20 = 0,
    SMA9_SMA50 = 1
};
input SMACondition inCondition = SMA9_SMA20; // Dieu kien vao lenh
extern double inVolume = 0.01;        // Khoi luong
input int inStochK=5;                 //Stochastic K Period, default 5
input int inStochD=3;                 //Stochastic D Period, default 3
input int inStochSlowing=3;           //Stochastic Slowing, default 3
ENUM_MA_METHOD ma_method    = MODE_SMA; // Moving Average Type
ENUM_STO_PRICE sto_method   = STO_LOWHIGH; // Calculation is based on Low/High prices
ENUM_APPLIED_PRICE ma_applied_price = PRICE_CLOSE;
// co the them extern neu cho phep chinh sua enable/disable mua/ban
// 2 bien nay cho phep mở rộng, có thể xóa
bool isBuyAllowed = true;
bool isSellAllowed = true;

bool isStochBuyAllowed=false;
bool isStochSellAllowed=false;

bool isSMABuyAllowed=false;
bool isSMASellAllowed=false;

int retryNumber = 10; // number of attempt
int count = 0;

// TODO: SL - Dat ngay day zigzag gan nhat truoc do
//double kStopLoss=20;             //Stop loss in pips
// TODO: TP1 - Co nen dong cua duoi MA9
double kTakeProfit=100;          //Take profit in pips
int kSlippage=0; //  no information

bool tradeOnce = false; // for test only
int period_MA_short=9;
int period_MA_long=0;
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
    period_MA_long = (inCondition==SMA9_SMA20) ? 20 : 50;
// 22.09.21: Dem nen (bat dau cay nen moi)
    /*
    datetime batdaucaynenmoi = iTime(Symbol(),0,0);
    if (TimeCurrent() == batdaucaynenmoi) return;
    else batdaucaynenmoi = iTime(Symbol(),0,0);
    */
    checkOrdersAllowed();
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void checkOrdersAllowed()
{
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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void kiemtraDieuKien()
{
// DK1: stoch xanh cat len do
    double stm0 = iStochastic (Symbol(),0,inStochK,inStochD,inStochSlowing,ma_method,sto_method,MODE_MAIN,0);
    double stm1 = iStochastic (Symbol(),0,inStochK,inStochD,inStochSlowing,ma_method,sto_method,MODE_MAIN,1);
    double sts0 = iStochastic (Symbol(),0,inStochK,inStochD,inStochSlowing,ma_method,sto_method,MODE_SIGNAL,0);
    double sts1 = iStochastic (Symbol(),0,inStochK,inStochD,inStochSlowing,ma_method,sto_method,MODE_SIGNAL,1);
//Print("stm0: ", stm0, ", sts0: ", sts0, "- stm1: ", stm1, ", sts1: ", sts1);
    isStochBuyAllowed = (stm1 < sts1 && stm0 > sts0);
    isStochSellAllowed = (stm1>sts1 && stm0<sts0);
    testOrder(OP_BUY); // test only, will be removed
    if (isStochBuyAllowed || isStochSellAllowed) {
        count++;
        double ma9_1, ma9_2;
        double lma1, lma2;
        // SMA9 cat lên SMA20, tính nen 2,3,4 ke tu khi cat lên
        ma9_1 = iMA(NULL, 0, 9, 0, period_MA_short, ma_applied_price, 1);
        ma9_2 = iMA(NULL, 0, 9, 0, period_MA_short, ma_applied_price, 2);
        //Print("ma9_1: ", ma9_1, ", ma9_2: ", ma9_2);
        lma1 = iMA(NULL, 0, period_MA_long, 0, ma_method, ma_applied_price,1);
        lma2 = iMA(NULL, 0, period_MA_long, 0, ma_method, ma_applied_price, 2);
        isSMABuyAllowed = (ma9_2 < lma2) && (ma9_1 > lma1);
        isSMASellAllowed = (ma9_2 > lma2) && (ma9_1 < lma1);
        // Trong vong 4 cay nen neu SMA9 cat len SMA20/SMA50
        if (count <= 4) {
            double zigzag_bottom = findStoploss();
            double stopLoss=0;
            refine_volume();
            inVolume = NormalizeDouble(inVolume,Digits);
            // ORDER BUY
            if (isStochBuyAllowed && isSMABuyAllowed) {
                stopLoss=Ask-zigzag_bottom*Point;
                bool isOrderPlaced = false;
                for(int i=0; i<retryNumber && !isOrderPlaced; i++) {
                    int ticketNumber = OrderSend(_Symbol,OP_BUY,inVolume,Ask,kSlippage,0,0,"STO-BUY",0,0,Green);
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
                // IF BUY -> CLOSE ALL SELL ORDERS
                // Khi tăng giá mình mua thì đóng lệnh BUY?
                //closeOrders(OP_SELL);
            }
            // ORDER SELL
            if (isStochSellAllowed && isSMASellAllowed) {
                stopLoss=Bid+zigzag_bottom*Point;
                bool isOrderPlaced = false;
                for(int i=0; i<retryNumber && !isOrderPlaced; i++) {
                    int ticketNumber = OrderSend(_Symbol,OP_SELL,inVolume,Bid,kSlippage,0,0,"STO-SELL",0,0,Green);
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
                // IF SELL -> CLOSE ALL BUY ORDERS
                // Khi giảm giá thì đóng lệnh BUY?
                //closeOrders(OP_BUY);
            }
        } else count = 0;
    } else count = 0;
// TP1: Co nen dong cua duoi MA9 => CLOSE BUY ORDERS
    double ma9_0 = iMA(NULL, 0, 9, 0, ma_method, ma_applied_price, 0);
    Print("Close1: ", iClose(Symbol(),0,1), " ma9_0: ", ma9_0);
    for(int i = 0; i < OrdersTotal() && (iClose(Symbol(),0,1)<ma9_0); i++ ) {
        if( OrderSelect( i, SELECT_BY_POS, MODE_TRADES ) == false ) {
            Print("ERROR - Failed to select the order - ", GetLastError());
            continue;
        }
        if(OrderSymbol()==_Symbol && OrderType()==OP_BUY) {
            for(int j=1; j<retryNumber; j++) {
                bool res=OrderClose(OrderTicket(),OrderLots(),OrderClosePrice(),kSlippage,Red);
                if(res) {
                    Print("TRADE - CLOSE - Order ", OrderTicket()," closed at price ",OrderClosePrice());
                    break;
                } else Print("ERROR - CLOSE - error closing order ", OrderTicket()," return error: ",GetLastError());
                Sleep(50);
            }
        }
    }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void testOrder(int inCommand)
{
    if (tradeOnce) return;
    tradeOnce = true;
    RefreshRates();
    double openPrice=0;
    double tpPrice = 0;
    if(inCommand == OP_BUY) {
        openPrice = Ask; // =MarketInfo(_Symbol,MODE_ASK);=
    }
    if(inCommand == OP_SELL) {
        openPrice = Bid; // =MarketInfo(_Symbol,MODE_BID);
    }
//slPrice = NormalizeDouble(slPrice,Digits); // replace Digits = MarketInfo(_Symbol,MODE_DIGITS)
//tpPrice = NormalizeDouble(tpPrice,Digits);
    refine_volume();
    inVolume = NormalizeDouble(inVolume,Digits);
// gia tri stop loss la day ZigZag gan nhat truoc do
    double new_StopLoss = findStoploss();
    Print("new_StopLoss: ", new_StopLoss);
    bool isOrderPlaced = false;
    for(int i=0; i<retryNumber && !isOrderPlaced; i++) {
        int ticketNumber = OrderSend(_Symbol,inCommand,inVolume,openPrice,kSlippage,0,0,"",0,0,Green);
        if(ticketNumber > 0) {
            /*
            for (int j=0;j<retryNumber && new_StopLoss>0;j++) {
               if (OrderModify(ticketNumber,openPrice,NormalizeDouble(new_StopLoss,Digits),tpPrice,0,clrNONE)) {
                  isOrderPlaced = true;
                  break;
               } else {
                  Print("ERROR - NEW - error modifying order, return error: ",GetLastError());
               }
               Sleep(50);
            }*/
        } else Print("ERROR - NEW - error sending order, return error: ",GetLastError());
    }
    Print(__FUNCTION__, " done.");
    return;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void closeOrders(int inCmd)
{
    for(int i = 0; i < OrdersTotal(); i++) {
        if( OrderSelect( i, SELECT_BY_POS, MODE_TRADES ) == false ) {
            Print("ERROR - Failed to select the order - ", GetLastError());
            Sleep(50);
            continue;
        }
        if(OrderSymbol()==_Symbol && OrderType()==inCmd) {
            for(int j=1; j<retryNumber; j++) {
                bool res=OrderClose(OrderTicket(),OrderLots(),OrderClosePrice(),kSlippage,Red);
                if(res) {
                    Print("TRADE - CLOSE - Order ", OrderTicket()," closed at price ",OrderClosePrice());
                    break;
                } else {
                    Print("ERROR - CLOSE - error closing order ", OrderTicket()," return error: ",GetLastError());
                    Sleep(50);
                }
            }
        }
    }
}

// ZigZag
double findStoploss(void)
{
// ZigZag: mode is BufferIndex:
// 0: double ExtZigzagBuffer[]
// 1: double ExtHighBuffer[]
// 2: double ExtLowBuffer[]
//                                    mode,shift
// iCustom(Symbol(),0,"ZigZag",12,5,3,0,i);
    int counted_bars=IndicatorCounted();
    int limit=0;
    limit = Bars-counted_bars;
    double prev_low = 0;
    for (int shift=0; shift<limit; shift++) {
        prev_low = iCustom(Symbol(),0,"ZigZag",12,5,3,0,shift);
        if(prev_low>0.1 && Low[shift]==prev_low) {
            break;
        }
    }
    return prev_low;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void refine_volume()
{
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
