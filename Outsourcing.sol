// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

interface IERC20 {

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function deposit(uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);

}

/** 
 * @title OutsourcingContract
 * @dev Implements create job process along with transfer 25% of budget to project manager
 */
contract Outsourcing {
    //address constant private WETH = 0x19bFB4C85746bCaafC64d80c509409fDE7657b2f;
    address private projectManager;
    uint256 public rateJava;
    uint256 public ratePython;
    uint256 _cancel_fee = 5;
    uint256 _milestone_charge = 25;
    uint256 _margin = 20;
    address constant private WETH = 0xE0543B8fd7c18ac3EeF78c45f7d222De3bc74dEd;

    enum Language { JAVA, PYTHON }
    enum JobStatus { 
        SUBMITTED, // 0. PM
        APPROVED, // 1. Client [1/4]
        BUILD_AND_TEST, // 2. Dev
        PENDING_COMPLETE_BUILD_AND_TEST, // 3. Dev
        COMPLETE_BUILD_AND_TEST, // 4. PM
        CLIENT_ACCEPT_BUILD_AND_TEST, // 5. Client [2/4]
        PENDING_CLIENT_CONFIRM_UAT, // 6. PM
        CLIENT_ACCEPT_UAT_COMPLETE, // 7. Client [3/4]
        PENDING_IT_CONFIRM_DEPLOYMENT, // 8. Dev
        PENDING_CLIENT_CONFIRM_COMPLETED, // 9. PM
        CLIENT_ACCEPT_DELIVERY_COMPLETE, // 10. Client [4/4]
        COMPLETE, // 11. PM
        CANCEL // 12
    }

    mapping (address => Developer) public developers;
    mapping (address => Client) public clients;
    mapping(string => Project) public ticket;
    address[] private developerList;
    address[] private clientList;
    string[] private projectList;
    
    
    // Struct develop => enum, lang, rate, name -> condition rate < manday rate && not dupplicate
    struct Developer {
        address addr;
        string name;
        Language lang;
        uint256 rate;
        bool available;
        bool registered;
    }

    // Struct client => company name, name, role -> condition rate < manday rate && not dupplicate
    struct Client {
        address addr;
        string name;
        string position;
        string company;
        bool registered;
    }

    struct Project {
        string ticketId;
        string project_name;
        JobStatus status;
        address client;
        address[] listDevelopers;
        mapping (address => bool) developers;
        string checksum;
        uint256 mandays;
        uint256 budget;
        uint256 paidAmount;
        bool closed;
    }

    // event for EVM logging
    event OwnerSet(address indexed oldOwner, address indexed newOwner);
    event RegisterDeveloper(address _addr, string name, Language lang, uint256 rate);
    event RegisterClient(address _addr, string _name, string _position, string _company);
    event SignAgreement(string ticketId, string project_name, uint budget, address client, address manager, address[] _developers);
    event ChangeStatus(string ticketId, address _addr, JobStatus old_status, JobStatus new_status);
    
    // modifier to check if caller is owner
    modifier isOwner() {
        // If the first argument of 'require' evaluates to 'false', execution terminates and all
        // changes to the state and to Ether balances are reverted.
        // This used to consume all gas in old EVM versions, but not anymore.
        // It is often a good idea to use 'require' to check if functions are called correctly.
        // As a second argument, you can also provide an explanation about what went wrong.
        require(msg.sender == projectManager, "Caller is not owner");
        _;
    }

    modifier isCientExisting(address _addr) {
        Client memory tmpClient = clients[_addr];
        require(tmpClient.registered == false, "Your address already registered.");
        _;

        // Client memory temp = clients[_addr];
        // bytes memory tempEmptyStringTest = bytes(temp.company); // Uses memory
        
        // require(tempEmptyStringTest.length == 0, "Your address already registered.");
        // _;
    }

    modifier isDeveloperExisting(address _addr) {
        Developer memory tmpDeveloper = developers[_addr];
        require(tmpDeveloper.registered == false, "Your address already registered.");
        _;

        // Developer memory temp = developers[_addr];
        // bytes memory tempEmptyStringTest = bytes(temp.name); // Uses memory
        
        // require(tempEmptyStringTest.length == 0, "Your address already registered.");
        // _;
    }

    /**
     * @dev Set contract deployer as owner
     */
    constructor() {
        projectManager = msg.sender; // 'msg.sender' is sender of current call, contract deployer for a constructor
        emit OwnerSet(address(0), projectManager);
    }

    /**
     * @dev Change owner
     * @param newOwner address of new owner
     */
    function changeOwner(address newOwner) public isOwner {
        emit OwnerSet(projectManager, newOwner);
        projectManager = newOwner;
    }

    /**
     * @dev Return owner address 
     * @return address of owner
     */
    function getOwner() external view returns (address) {
        return projectManager;
    }

    function setRateJava(uint256 _rate) public isOwner {
        rateJava = _rate;
    }

    function setRatePython(uint256 _rate) public isOwner {
        ratePython = _rate;
    }

    function setCancelFee(uint256 _fee) public isOwner {
        _cancel_fee = _fee;
    }

    function setMilestoneCharge(uint256 _rate) public isOwner {
        _milestone_charge = _rate;
    }

    function setMargin(uint256 _rate) public isOwner {
        _margin = _rate;
    }

    function registerDeveloper(string memory _name, Language _lang, uint256 _rate) public isDeveloperExisting(msg.sender) {
        require(bytes(_name).length > 0, "Name at least 1 charactor.");
        require(_rate > 0, "Rate must great than 0");

        Developer storage developer = developers[msg.sender];
        developer.addr = msg.sender;
        developer.name = _name;
        developer.lang = _lang;
        developer.rate = _rate;
        developer.available = true;
        developer.registered = true;

        developerList.push(msg.sender);

        emit RegisterDeveloper(msg.sender, _name, _lang, _rate);
    }

    function registerClient(string memory _name, string memory _position, string memory _company) public isCientExisting(msg.sender) {
        require(bytes(_company).length > 0, "Company name at least 1 charactor.");

        Client storage client = clients[msg.sender];
        client.addr = msg.sender;
        client.name = _name;
        client.position = _position;
        client.company = _company;
        client.registered = true;

        clientList.push(msg.sender);

        emit RegisterClient(msg.sender, _name, _position, _company);
    }

    //1a833da63a6b7e20098dae06d06602e1
    //0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    // 0x19bFB4C85746bCaafC64d80c509409fDE7657b2f
    // 0.01 ETH = 10000000000000000
    // 0.1 ETH = 100000000000000000
    function signAgreement(address[] memory _developers, address client, string memory ticketId, string memory project_name, uint256 _mandays, uint256 budget, string memory _checksum) public isOwner {
        // Validate
        require(budget > 0);
        require(_developers.length > 0);
        require(ticket[ticketId].closed == false, "The project is now complete.");
        require(ticket[ticketId].budget == 0, "The ticket is already in use.");
        //require(bytes(clients[client].company).length > 0, "The client has not yet been registered.");
        require(clients[client].registered, "The client has not yet been registered.");

        // Cal over budget developers
        uint256 totalBudgetDevelopers = 0;
        for (uint i = 0; i < _developers.length; i++) {
            Developer memory dev = developers[_developers[i]];
            uint256 rate_dev = dev.rate;
            totalBudgetDevelopers += (_mandays * rate_dev);
        }
        require((budget - totalBudgetDevelopers) > (budget * (_margin/100)), "Invalid budget margin!!!");

        Project storage data = ticket[ticketId];
        data.ticketId = ticketId;
        data.project_name = project_name;
        data.status = JobStatus.SUBMITTED;
        data.client = client;
        data.listDevelopers = _developers;
        // initial developers
        for (uint i = 0; i < _developers.length; i++) {
            require(bytes(developers[_developers[i]].name).length > 0, "The developers aren't registered.");
            data.developers[_developers[i]] = true; // set valid developer

            // set not available
            Developer storage dev = developers[_developers[i]];
            dev.available = false;
        }

        data.checksum = _checksum;
        data.mandays = _mandays;
        data.budget = budget;
        data.paidAmount = 0;
        data.closed = false;

        projectList.push(ticketId);

        emit SignAgreement(ticketId, project_name, budget, client, msg.sender, _developers);
    }

    // 0x19bFB4C85746bCaafC64d80c509409fDE7657b2f
    // 0.01 ETH = 10000000000000000
    // 0.1 ETH = 100000000000000000
    function changeStatus(string memory ticketId, JobStatus _status) public {
        // require existing project
        require(ticket[ticketId].budget > 0, "The ticket does not exist.");
        require(ticket[ticketId].closed == false, "The project is now complete.");

        Project storage data = ticket[ticketId];
        JobStatus currentStatus = data.status;
        uint256 _budget = data.budget;
                
        if (_status == JobStatus.APPROVED) {
            // action role : Client
            require(currentStatus == JobStatus.SUBMITTED, "Invalid job status!");
            require(data.client == msg.sender, "Client only!!!");

            // Client transfer from WETH to OutsourcingContract
            IERC20(WETH).transferFrom(msg.sender, address(this), _budget); 

            // transfer 25% of budget to ProjectManager (1/4)
            IERC20(WETH).transfer(projectManager, _budget * _milestone_charge / 100);
            
            data.paidAmount = data.paidAmount + (_budget * _milestone_charge / 100);
        }

        if (_status == JobStatus.BUILD_AND_TEST) {
            // action role : Client
            require(currentStatus == JobStatus.APPROVED, "Invalid job status!");
            require(data.developers[msg.sender] || msg.sender == projectManager , "PM or Dev only!!!");
        }

        if (_status == JobStatus.PENDING_COMPLETE_BUILD_AND_TEST) {
            require(currentStatus == JobStatus.BUILD_AND_TEST, "Invalid job status!");
            require(data.developers[msg.sender] || msg.sender == projectManager , "PM or Dev only!!!");
        }

        if (_status == JobStatus.COMPLETE_BUILD_AND_TEST) {
            // action role : Project Manager
            require(currentStatus == JobStatus.PENDING_COMPLETE_BUILD_AND_TEST, "Invalid job status!");
        }

        if (_status == JobStatus.CLIENT_ACCEPT_BUILD_AND_TEST) {
            // action role : Client
            require(currentStatus == JobStatus.COMPLETE_BUILD_AND_TEST, "Invalid job status!");
            require(data.client == msg.sender, "Client only!!!");

            // transfer 25% of budget to ProjectManager (2/4) ---> 4
            IERC20(WETH).transfer(projectManager, _budget * _milestone_charge / 100);
            
            data.paidAmount = data.paidAmount + (_budget * _milestone_charge / 100);
        }

        if (_status == JobStatus.PENDING_CLIENT_CONFIRM_UAT) {
            // action role : DEV
            require(currentStatus == JobStatus.CLIENT_ACCEPT_BUILD_AND_TEST, "Invalid job status!");
            require(data.developers[msg.sender] || msg.sender == projectManager , "PM or Dev only!!!");
        }

        if (_status == JobStatus.CLIENT_ACCEPT_UAT_COMPLETE) {
            // action role : Client
            require(currentStatus == JobStatus.PENDING_CLIENT_CONFIRM_UAT, "Invalid job status!");
            require(data.client == msg.sender, "Client only!!!");

            // transfer 25% of budget to ProjectManager (3/4) ---> 6
            IERC20(WETH).transfer(projectManager, _budget * _milestone_charge / 100);
            
            data.paidAmount = data.paidAmount + (_budget * _milestone_charge / 100);
        }

        if (_status == JobStatus.PENDING_IT_CONFIRM_DEPLOYMENT) {
            // action role : DEV
            require(currentStatus == JobStatus.CLIENT_ACCEPT_UAT_COMPLETE, "Invalid job status!");
            require(data.developers[msg.sender] || msg.sender == projectManager , "PM or Dev only!!!");
        }

        if (_status == JobStatus.PENDING_CLIENT_CONFIRM_COMPLETED) {
            // action role : CLIENT
            require(currentStatus == JobStatus.PENDING_IT_CONFIRM_DEPLOYMENT, "Invalid job status!");
            require(data.developers[msg.sender] || msg.sender == projectManager , "PM or Dev only!!!");
        }

        if (_status == JobStatus.PENDING_IT_CONFIRM_DEPLOYMENT) {
            // action role : DEV
            require(currentStatus == JobStatus.CLIENT_ACCEPT_UAT_COMPLETE, "Invalid job status!");
            require(data.developers[msg.sender] || msg.sender == projectManager , "PM or Dev only!!!");
        }

        if (_status == JobStatus.PENDING_CLIENT_CONFIRM_COMPLETED) {
            // action role : DEV
            require(currentStatus == JobStatus.PENDING_IT_CONFIRM_DEPLOYMENT, "Invalid job status!");
            require(data.developers[msg.sender] || msg.sender == projectManager , "PM or Dev only!!!");
        }

        if (_status == JobStatus.CLIENT_ACCEPT_DELIVERY_COMPLETE) {
            // action role : Client
            require(currentStatus == JobStatus.PENDING_CLIENT_CONFIRM_COMPLETED, "Invalid job status!");
            require(data.client == msg.sender, "Client only!!!");

            // transfer 25% of budget to ProjectManager (4/4) ---> 9
            IERC20(WETH).transfer(projectManager, _budget * _milestone_charge / 100);
            
            data.paidAmount = data.paidAmount + (_budget * _milestone_charge / 100);
        }

        if (_status == JobStatus.COMPLETE) {
            // action role : Project Manager
            require(currentStatus == JobStatus.CLIENT_ACCEPT_DELIVERY_COMPLETE, "Invalid job status!");
            require(msg.sender == projectManager, "Project manager only!!!");

            for (uint i = 0; i < data.listDevelopers.length; i++) {
                Developer storage dev = developers[data.listDevelopers[i]];
                // set available
                dev.available = true;

                // pay to developer
                uint256 totalIncome = data.mandays * dev.rate;
                //IERC20(WETH).transfer(dev.addr, totalIncome);
                IERC20(WETH).transferFrom(msg.sender, dev.addr, totalIncome); 
            }
            // set closed ticket
            data.closed = true;
        }

        if (_status == JobStatus.CANCEL) {
            // action role : Client
            require(currentStatus < JobStatus.COMPLETE, "Invalid job status!");
            require(data.client == msg.sender, "Client only!!!");

            // return currentBudget - fee from weth to client
            
            uint256 remainingBudget = _budget - data.paidAmount;
            uint256 fee = remainingBudget * _cancel_fee / 100;
            uint256 returnClientBalance = remainingBudget - fee;

            IERC20(WETH).transfer(msg.sender, returnClientBalance);

            // Transfer fee to PM
            IERC20(WETH).transfer(projectManager, fee);

            for (uint i = 0; i < data.listDevelopers.length; i++) {
                Developer storage dev = developers[data.listDevelopers[i]];
                
                // set available
                dev.available = true;

                // Pay to developers
                //uint256 totalIncome = data.mandays * dev.rate;
                //IERC20(WETH).transfer(dev.addr, totalIncome);
            }
            // set closed ticket
            data.closed = true;
        }
        
        // Set status project
        data.status = _status;

        emit ChangeStatus(ticketId, msg.sender, currentStatus, _status);
    }

    function withdraw(uint balance) public {
        IERC20(WETH).transfer(msg.sender, balance);
    }

    function getProjectList() public view returns (string[] memory) {
        return projectList;
    }

    function getDevelopers() public view returns (address[] memory) {
        return developerList;
    }

    function getClients() public view returns (address[] memory) {
        return clientList;
    }

    function getCancelFee() public view returns (uint256) {
        return _cancel_fee;
    }
    function getMilestoneChage() public view returns (uint256) {
        return _milestone_charge;
    }

    function getMargin() public view returns (uint256) {
        return _margin;
    }
}
