pragma solidity ^0.4.21;
import "./SafeMath.sol";
import "./IDataSaaS.sol";

/*
*@title MarketPlace contract
*/


contract DataSaas is IDataSaaS {
    
    using SafeMath for uint256;
    using SafeMath for uint;
    
    struct Order{
        bytes32 dataSetName;
        address buyer;
        address seller;
        uint price;
        uint startTime;
        uint endTime;
        bool isPaid;
        bool isOrder;
        bool isRefundPaid;
        
    }
    
    struct provider{
        address owner;
        address[] members;
        uint price;
        uint deposit;
        bytes32 name;
        bool isPunished;
        uint256 punishTimestamp;
        bool isProvider;
        bool isActive;
    }
    
    uint public constant FIXED_SUBSCRIPTION_PERIOD = 604800; //1 week
    
    mapping(bytes32 => Order[]) hOrder;
    mapping(bytes32 => provider) hProvider;
    mapping(address => uint256) public balance;
    
    uint numProviders;
    address private owner;
    
    
    /* modifiers */
    modifier validDataProvider(bytes32 _dataSourceName){
        require(hProvider[_dataSourceName].isProvider);
        require(hProvider[_dataSourceName].isActive);
        require(!hProvider[_dataSourceName].isPunished);  
        _;      
    }
    modifier uniqueDataName(bytes32 _dataSourceName) {
        require(!hProvider[_dataSourceName].isProvider);
        _;
    }
    modifier validPrice (uint256 _price){
        require(_price.add(1) > _price); //overflow
        _;
    }
    modifier onlyDataProvider(bytes32 _dataSourceName){
        require(hProvider[_dataSourceName].isProvider);
        require(hProvider[_dataSourceName].owner == msg.sender);
        _;
    }
    modifier onlyOwner(){
        require(owner == msg.sender);
        _;
    }
    
    constructor() public {
     owner = msg.sender;
    }
    

    function register(bytes32 _dataSetName, uint256 price, address _company, address[] _cMembers) 
    public
    payable
    uniqueDataName(_dataSetName)
    validPrice(price)
    returns (bool){
        uint256 deposit = price;
        
        hProvider[_dataSetName].name = _dataSetName;
        hProvider[_dataSetName].price = price;
        hProvider[_dataSetName].deposit = deposit;
        hProvider[_dataSetName].owner = _company;
        hProvider[_dataSetName].members = _cMembers;
        hProvider[_dataSetName].isPunished = false;
        hProvider[_dataSetName].isProvider = true;
        hProvider[_dataSetName].isActive = true;
        hProvider[_dataSetName].members.push(_company);
        numProviders = numProviders.add(1);
        emit Registered(_company,_dataSetName,price,true);
        return true;
        
    }
    
    function subscribe(bytes32 _dataSetName, uint _weeks) 
    public 
    payable
    validDataProvider(_dataSetName)
    returns (bool success){
        address[] memory iMembers = hProvider[_dataSetName].members;
        uint256 length = iMembers.length;
        uint256 fund = (hProvider[_dataSetName].price*_weeks)/length;
        
        for(uint i=0;i<length;i++){
         bool result =   safeToMarketPlaceTransfer(msg.sender,iMembers[i],fund);
        }
        require(result); // revet state if failed
        
        // update order
        hOrder[_dataSetName].push(Order({
            dataSetName : _dataSetName,
            buyer : msg.sender,
            seller : hProvider[_dataSetName].owner,
            price : hProvider[_dataSetName].price * _weeks,
            startTime : now,
            endTime : now + (FIXED_SUBSCRIPTION_PERIOD * _weeks),
            isPaid : false,
            isOrder : true,
            isRefundPaid : false
            }));
      
        emit Subscribed(msg.sender,
            _dataSetName,
            hProvider[_dataSetName].owner,
            hProvider[_dataSetName].price,
            true);
        success = true;
    }
    
    function safeToMarketPlaceTransfer(address _from, address _to, uint256 _amount) 
    internal
    validPrice(_amount)
    returns (bool){
         require(_from != address(0));
         
         uint256 _payment = _amount;
         _amount = 0;
         _to.transfer(_payment);
         emit SubscriptionDeposited(_from, _to, _amount);
         return true;
    }
    
    function setPunishProvider(bytes32 _dataSetName, bool _isPunished) 
    public 
    payable
    onlyOwner 
    returns (bool success){
        require(hProvider[_dataSetName].isProvider);
        hProvider[_dataSetName].isPunished = _isPunished;
        if(_isPunished){
            hProvider[_dataSetName].punishTimestamp = now;
            hProvider[_dataSetName].isActive = false;
        }else{
            hProvider[_dataSetName].punishTimestamp = 0;
            hProvider[_dataSetName].isActive = true;
        }
        emit ProviderPunishStatus(hProvider[_dataSetName].owner,_dataSetName,_isPunished);
        success = true;
    }
    
    function refundSubscriber(bytes32 _dataSetName) 
    public 
    returns
    (bool success){
        require(hProvider[_dataSetName].isProvider);
        uint256 refundAmount = 0;
        uint size = hOrder[_dataSetName].length;
        for(uint i=0; i<size ;i++){
            if(hOrder[_dataSetName][i].buyer == msg.sender){
                uint256 refund = handleOrderRefundCalc(hOrder[_dataSetName][i]);
                if(refund > 0 && !hOrder[_dataSetName][i].isRefundPaid){ // double check payment
                    hOrder[_dataSetName][i].isRefundPaid = true;// mark refund as paid
                    refundAmount = refundAmount.add(refund);
                   
                }
            }
        }
        
        require(safeToSubscriberTransfer(msg.sender,refundAmount));
        emit SubscriberRefund(msg.sender,_dataSetName,refundAmount);
        success = true;
}
    
   
    function handleOrderRefundCalc(Order order)
    internal
    view
    returns(uint256 refundAmount){
        refundAmount = 0;
        if(!order.isRefundPaid){ //order not paid 
            if(hProvider[order.dataSetName].isPunished){ // provider is punished
                if(hProvider[order.dataSetName].punishTimestamp > order.startTime && hProvider[order.dataSetName].punishTimestamp < order.endTime){ // punished before the subscription is expired
                   refundAmount = order.price.sub(calcRelativeWithdraw(order)); // price - withdrawPrice
                }
            }
        }
        return refundAmount;
    }
    
    function safeToSubscriberTransfer(address _subscriber,uint256 _amount) 
    internal 
    validPrice(_amount)
    returns (bool){
        require(_amount > 0);
        require(_subscriber == msg.sender);
       _subscriber.transfer(_amount);
        return true;
    }
    
    function withdrawProvider(bytes32 _dataSetName) 
    public 
    onlyDataProvider(_dataSetName) 
    returns (bool success){
        // calculate the withdraw amount 
        uint256 withdrawAmount = 0;
        uint orderSize = hOrder[_dataSetName].length;
        for(uint i=0;i<orderSize;i++){
            uint256 withdraw = handleOrderWithdrawCalc(hOrder[_dataSetName][i]);
            if(withdraw > 0 && !hOrder[_dataSetName][i].isPaid){ // double check
                hOrder[_dataSetName][i].isPaid = true; // mark order as paid 
                withdrawAmount = withdrawAmount.add(withdraw); 
            }
            
        }
        // transfer ENG's to the provider -revert state if faild
        require(safeToProviderTransfer(_dataSetName,withdrawAmount)); 
      // emit ProviderWithdraw(hProvider[_dataSetName].owner,_dataSetName,withdrawAmount);
        return true;
    }
    
     function handleOrderWithdrawCalc(Order order)
     internal
     view
     returns(uint256 orderAmount){
        orderAmount = 0;
        if(!order.isPaid){ // if not paid yet 
                if(hProvider[order.dataSetName].isPunished){ // if punished
                    if(hProvider[order.dataSetName].punishTimestamp >= order.endTime){ // punished after expiration date
                        return order.price;
                    }else{ // punished before expiration date
                        return calcRelativeWithdraw(order); //(punishtime / endtime) * amount
                    }
                }else{ // not punished - return full amount
                    return order.price;
                }
        }
        return orderAmount;
    }
    
    function calcRelativeWithdraw(Order order) internal view returns(uint256 relativeAmount){
        require(hProvider[order.dataSetName].isPunished);
         // (punishTime- startTime) * PRICE / (endTime - startTime);
        uint256 price = order.price;
        uint256 a = (hProvider[order.dataSetName].punishTimestamp.sub(order.startTime)).mul(price);
        uint256 b = order.endTime.sub(order.startTime);
        return SafeMath.div(a,b);
    }
    
    function safeToProviderTransfer(bytes32 _dataSetName,uint256 _amount) 
    internal 
    validPrice(_amount)
    onlyDataProvider(_dataSetName) 
    returns (bool){
         require(_amount > 0);
         require(hProvider[_dataSetName].owner != address(0));
         hProvider[_dataSetName].owner.transfer(_amount);
         emit TransferToProvider(hProvider[_dataSetName].owner,_dataSetName,_amount);
         return true;
    }
    
    function getRefundAmount(address _subscriber , bytes32 _dataSourceName) 
    public 
    view 
    returns(uint256 refundAmount){
        require(_subscriber != address(0));
        require(hProvider[_dataSourceName].isProvider);
        refundAmount = 0;
        uint size = hOrder[_dataSourceName].length;
        for(uint i=0; i< size ; i++){
            if(hOrder[_dataSourceName][i].buyer == _subscriber){
                refundAmount = refundAmount.add(handleOrderRefundCalc(hOrder[_dataSourceName][i]));
            }
        }
        return refundAmount;
    }
    
    function updateDataSourcePrice(bytes32 _dataSourceName, uint256 _newPrice) 
    external 
    onlyDataProvider(_dataSourceName)
    validPrice(_newPrice)
    returns (bool success){
        hProvider[_dataSourceName].price = _newPrice;
        emit PriceUpdate(msg.sender, _dataSourceName,_newPrice);
        success = true;
    }
    
    function changeDataSourceActivityStatus(bytes32 _dataSourceName,bool _isActive) 
    external 
    onlyDataProvider(_dataSourceName) 
    returns (bool success){
        hProvider[_dataSourceName].isActive = _isActive;
        emit ActivityUpdate(msg.sender, _dataSourceName, _isActive);
        success = true;
    }

}