//
//  JTAppleCalendarView.swift
//  JTAppleCalendar
//
//  Created by JayT on 2016-03-01.
//  Copyright © 2016 OS-Tech. All rights reserved.
//

let cellReuseIdentifier = "JTDayCell"

let NUMBER_OF_DAYS_IN_WEEK = 7

let MAX_NUMBER_OF_DAYS_IN_WEEK = 7                              // Should not be changed
let MIN_NUMBER_OF_DAYS_IN_WEEK = MAX_NUMBER_OF_DAYS_IN_WEEK     // Should not be changed
let MAX_NUMBER_OF_ROWS_PER_MONTH = 6                            // Should not be changed
let MIN_NUMBER_OF_ROWS_PER_MONTH = 1                            // Should not be changed

let FIRST_DAY_INDEX = 0
let NUMBER_OF_DAYS_INDEX = 1
let OFFSET_CALC = 2





/// Describes which month owns the date
public enum DateOwner: Int {
    /// Describes which month owns the date
    case ThisMonth = 0, PreviousMonthWithinBoundary, PreviousMonthOutsideBoundary, FollowingMonthWithinBoundary, FollowingMonthOutsideBoundary
}


/// Describes which month the cell belongs to
/// - ThisMonth: Cell belongs to the current month
/// - PreviousMonthWithinBoundary: Cell belongs to the previous month. Previous month is included in the date boundary you have set in your delegate
/// - PreviousMonthOutsideBoundary: Cell belongs to the previous month. Previous month is not included in the date boundary you have set in your delegate
/// - FollowingMonthWithinBoundary: Cell belongs to the following month. Following month is included in the date boundary you have set in your delegate
/// - FollowingMonthOutsideBoundary: Cell belongs to the following month. Following month is not included in the date boundary you have set in your delegate
///
/// You can use these cell states to configure how you want your date cells to look. Eg. you can have the colors belonging to the month be in color black, while the colors of previous months be in color gray.
public struct CellState {
    /// returns true if a cell is selected
    public let isSelected: Bool
    /// returns the date as a string
    public let text: String
    /// returns the a description of which month owns the date
    public let dateBelongsTo: DateOwner
    /// returns the date
    public let date: NSDate
    /// returns the day
    public let day: DaysOfWeek
    /// returns the row in which the date cell appears visually
    public let row: ()->Int
    /// returns the column in which the date cell appears visually
    public let column: ()->Int
    /// returns the section the date cell belongs to
    public let dateSection: ()->(dateRange:(start: NSDate, end: NSDate), month: Int)
    /// returns the position of a selection in the event you wish to do range selection
    public let selectedPosition: ()->SelectionRangePosition
    /// returns the cell frame. Useful if you wish to display something at the cell's frame/position
    public var cell: ()->JTAppleDayCell?
}

/// Selection position of a range-selected date cell
public enum SelectionRangePosition: Int {
    /// Selection position
    case Left = 1, Middle, Right, Full, None
}

/// Days of the week. By setting you calandar's first day of week, you can change which day is the first for the week. Sunday is by default.
public enum DaysOfWeek: Int {
    /// Days of the week.
    case Sunday = 1, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday
}

/// An instance of JTAppleCalendarView (or simply, a calendar view) is a means for displaying and interacting with a gridstyle layout of date-cells
public class JTAppleCalendarView: UIView {
    
    lazy var dateGenerator: JTAppleDateConfigGenerator = {
        var configurator = JTAppleDateConfigGenerator()
        configurator.delegate = self
        return configurator
    }()
    
    
    /// Configures the behavior of the scrolling mode of the calendar
    public enum ScrollingMode {
        case StopAtEachCalendarFrameWidth,
        StopAtEachSection,
        StopAtEach(customInterval: CGFloat),
        NonStopToSection(withResistance: CGFloat),
        NonStopToCell(withResistance: CGFloat),
        NonStopTo(customInterval: CGFloat, withResistance: CGFloat),
        None
        
        func  pagingIsEnabled()->Bool {
            switch self {
            case .StopAtEachCalendarFrameWidth: return true
            default: return false
            }
        }
    }
    
    /// Configures the size of your date cells
    public var itemSize: CGFloat?
    
    /// Enables and disables animations when scrolling to and from date-cells
    public var animationsEnabled = true
    /// The scroll direction of the sections in JTAppleCalendar.
    public var direction : UICollectionViewScrollDirection = .Horizontal {
        didSet {
            if oldValue == direction { return }
            let layout = generateNewLayout()
            calendarView.collectionViewLayout = layout
        }
    }
    /// Enables/Disables multiple selection on JTAppleCalendar
    public var allowsMultipleSelection: Bool = false {
        didSet {
            self.calendarView.allowsMultipleSelection = allowsMultipleSelection
        }
    }
    /// First day of the week value for JTApleCalendar. You can set this to anyday. After changing this value you must reload your calendar view to show the change.
    public var firstDayOfWeek = DaysOfWeek.Sunday {
        didSet {
            if firstDayOfWeek != oldValue { layoutNeedsUpdating = true }
        }
    }
    
    /// Alerts the calendar that range selection will be checked. If you are not using rangeSelection and you enable this, then whenever you click on a datecell, you may notice a very fast refreshing of the date-cells both left and right of the cell you just selected.
    public var rangeSelectionWillBeUsed = false
    
    var lastSavedContentOffset: CGFloat = 0.0
    var triggerScrollToDateDelegate: Bool? = true
    
    
    
    
    // Keeps track of item size for a section. This is an optimization
    var scrollInProgress = false
    private var layoutNeedsUpdating = false
    
    /// The object that acts as the data source of the calendar view.
    weak public var dataSource : JTAppleCalendarViewDataSource? {
        didSet {
            setupMonthInfoAndMap()
            updateLayoutItemSize(calendarView.collectionViewLayout as! JTAppleCalendarLayout)
            reloadData(checkDelegateDataSource: false)
        }
    }
    
    
    func setupMonthInfoAndMap() {
        let generatedData = setupMonthInfoDataForStartAndEndDate()
        monthInfo = generatedData.months
        monthMap = generatedData.monthMap
    }
    
    
    /// The object that acts as the delegate of the calendar view.
    weak public var delegate: JTAppleCalendarViewDelegate?

    var delayedExecutionClosure: [(()->Void)] = []
    
    #if os(iOS)
        var lastOrientation: UIInterfaceOrientation?
    #endif
    
    var currentSectionPage: Int {
        return (calendarView.collectionViewLayout as! JTAppleCalendarLayoutProtocol).sectionFromRectOffset(calendarView.contentOffset)
    }
  
    var startDateCache: NSDate {
        get { return cachedConfiguration.startDate }
    }
    
    var endDateCache: NSDate {
        get { return cachedConfiguration.endDate }
    }
    
    var calendar: NSCalendar {
        get { return cachedConfiguration.calendar }
    }
    
    lazy var cachedConfiguration: (startDate: NSDate, endDate: NSDate, numberOfRows: Int, calendar: NSCalendar, generateInDates: Bool, generateOutDates: OutDateCellGeneration) = {
        [weak self] in
        
        guard let  config = self!.dataSource?.configureCalendar(self!) else {
            assert(false, "DataSource is not set")
            return (startDate: NSDate(), endDate: NSDate(), 0, NSCalendar(calendarIdentifier: "nil")!, false, .off)
        }
        
        return (startDate: config.startDate, endDate: config.endDate, numberOfRows: config.numberOfRows, calendar: config.calendar, config.generateInDates, config.generateOutDates)
        }()
    
    // Set the start of the month
    lazy var startOfMonthCache: NSDate = {
        [weak self] in
        if let startDate = NSDate.startOfMonthForDate(self!.startDateCache, usingCalendar: self!.calendar) { return startDate }
        assert(false, "Error: StartDate was not correctly generated for start of month. current date was used: \(NSDate())")
        return NSDate()
        }()
    
    // Set the end of month
    lazy var endOfMonthCache: NSDate = {
        [weak self] in
        if let endDate = NSDate.endOfMonthForDate(self!.endDateCache, usingCalendar: self!.calendar) { return endDate }
        assert(false, "Error: Date was not correctly generated for end of month. current date was used: \(NSDate())")
        return NSDate()
        }()
    
    
    var theSelectedIndexPaths: [NSIndexPath] = []
    var theSelectedDates:      [NSDate]      = []
    
    /// Returns all selected dates
    public var selectedDates: [NSDate] {
        get {
            // Array may contain duplicate dates in case where out-dates are selected. So clean it up here
            return Array(Set(theSelectedDates)).sort()
        }
    }
    
    lazy var monthInfo : [month] = {
        [weak self] in
        let newMonthInfo = self!.setupMonthInfoDataForStartAndEndDate()
        self!.monthMap = newMonthInfo.monthMap
        return newMonthInfo.months
        }()
    
    lazy var monthMap: [Int:Int] = {
       [weak self] in
        let newMonthInfo = self!.setupMonthInfoDataForStartAndEndDate()
        self!.monthInfo = newMonthInfo.months
        return newMonthInfo.monthMap
    }()
    
    var numberOfMonths: Int {
        get { return monthInfo.count }
    }
    
    
    
    func numberOfItemsInSection(section: Int)-> Int {return collectionView(calendarView, numberOfItemsInSection: section)}
    
    /// Cell inset padding for the x and y axis of every date-cell on the calendar view.
    public var cellInset: CGPoint = CGPoint(x: 3, y: 3)
    var cellViewSource: JTAppleCalendarViewSource!
    var registeredHeaderViews: [JTAppleCalendarViewSource] = []

    /// Enable or disable swipe scrolling of the calendar with this variable
    public var scrollEnabled: Bool = true {
        didSet { calendarView.scrollEnabled = scrollEnabled }
    }
    
    // Configure the scrolling behavior
    public var scrollingMode: ScrollingMode = .StopAtEachCalendarFrameWidth {
        didSet {
            switch scrollingMode {
            case .StopAtEachCalendarFrameWidth:
                calendarView.decelerationRate = UIScrollViewDecelerationRateFast
            case .StopAtEach,.StopAtEachSection:
                calendarView.decelerationRate = UIScrollViewDecelerationRateFast
            case .NonStopToSection, .NonStopToCell, .NonStopTo, .None:
                calendarView.decelerationRate = UIScrollViewDecelerationRateNormal
            }
            
            #if os(iOS)
                switch scrollingMode {
                case .StopAtEachCalendarFrameWidth:
                    calendarView.pagingEnabled = true
                default:
                    calendarView.pagingEnabled = false
                }
            #endif
        }
    }
    
    lazy var calendarView : UICollectionView = {
        
        let layout = JTAppleCalendarLayout(withDelegate: self)
        layout.scrollDirection = self.direction
        
        let cv = UICollectionView(frame: CGRectZero, collectionViewLayout: layout)
        cv.dataSource = self
        cv.delegate = self
        cv.decelerationRate = UIScrollViewDecelerationRateFast
        cv.backgroundColor = UIColor.clearColor()
        cv.showsHorizontalScrollIndicator = false
        cv.showsVerticalScrollIndicator = false
        cv.allowsMultipleSelection = false
        #if os(iOS)
            cv.pagingEnabled = true
        #endif
        
        return cv
    }()
    
    private func updateLayoutItemSize (layout: JTAppleCalendarLayoutProtocol) {
        if dataSource == nil { return } // If the delegate is not set yet, then return
        // Default Item height
        var height: CGFloat = (self.calendarView.bounds.size.height - layout.headerReferenceSize.height) / CGFloat(cachedConfiguration.numberOfRows)
        // Default Item width
        var width: CGFloat = self.calendarView.bounds.size.width / CGFloat(MAX_NUMBER_OF_DAYS_IN_WEEK)

        if let userSetItemSize = self.itemSize {
            if direction == .Vertical { height = userSetItemSize }
            if direction == .Horizontal { width = userSetItemSize }
        }

        layout.itemSize = CGSize(width: width, height: height)
    }
    
    /// The frame rectangle which defines the view's location and size in its superview coordinate system.
    override public var frame: CGRect {
        didSet {
            calendarView.frame = CGRect(x:0.0, y:/*bufferTop*/0.0, width: self.frame.size.width, height:self.frame.size.height/* - bufferBottom*/)
            #if os(iOS)
                let orientation = UIApplication.sharedApplication().statusBarOrientation
                if orientation == .Unknown { return }
                if lastOrientation != orientation {
                    calendarView.collectionViewLayout.invalidateLayout()
                    let layout = calendarView.collectionViewLayout as! JTAppleCalendarLayoutProtocol
                    layout.clearCache()   
                    lastOrientation = orientation
                    updateLayoutItemSize(self.calendarView.collectionViewLayout as! JTAppleCalendarLayoutProtocol)
                    if delegate != nil { reloadData() }
                } else {
                    updateLayoutItemSize(self.calendarView.collectionViewLayout as! JTAppleCalendarLayoutProtocol)
                }
            #elseif os(tvOS)
                calendarView.collectionViewLayout.invalidateLayout()
                let layout = calendarView.collectionViewLayout as! JTAppleCalendarLayoutProtocol
                layout.clearCache()
                updateLayoutItemSize(self.calendarView.collectionViewLayout as! JTAppleCalendarLayoutProtocol)
                if delegate != nil { reloadData() }
                updateLayoutItemSize(self.calendarView.collectionViewLayout as! JTAppleCalendarLayoutProtocol)
            #endif
        }
    }
    
    /// Initializes and returns a newly allocated view object with the specified frame rectangle.
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.initialSetup()
    }
    
    
    /// Returns an object initialized from data in a given unarchiver. self, initialized using the data in decoder.
    required public init?(coder aDecoder: NSCoder) { super.init(coder: aDecoder) }
    
    /// Prepares the receiver for service after it has been loaded from an Interface Builder archive, or nib file.
    override public func awakeFromNib() { self.initialSetup() }
    
    /// Lays out subviews.
    override public func layoutSubviews() { self.frame = super.frame }
    
    // MARK: Setup
    func initialSetup() {
        self.clipsToBounds = true
        self.calendarView.registerClass(JTAppleDayCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        self.addSubview(self.calendarView)
    }
    
    func restoreSelectionStateForCellAtIndexPath(indexPath: NSIndexPath) {
        if theSelectedIndexPaths.contains(indexPath) {
            calendarView.selectItemAtIndexPath(indexPath, animated: false, scrollPosition: .None)
        }
    }
    
    func numberOfSectionsForMonth(index: Int) -> Int {
        if !monthInfo.indices.contains(index) { return 0 }
        return monthInfo[index].sections.count
    }
    
    func validForwardAndBackwordSelectedIndexes(forIndexPath indexPath: NSIndexPath)->[NSIndexPath] {
        var retval = [NSIndexPath]()
        if let validForwardIndex = calendarView.layoutAttributesForItemAtIndexPath(NSIndexPath(forItem: indexPath.item + 1, inSection: indexPath.section)) where
            theSelectedIndexPaths.contains(validForwardIndex.indexPath){
            retval.append(validForwardIndex.indexPath)
        }
        
        if let validBackwardIndex = calendarView.collectionViewLayout.layoutAttributesForItemAtIndexPath(NSIndexPath(forItem: indexPath.item - 1, inSection: indexPath.section)) where
            theSelectedIndexPaths.contains(validBackwardIndex.indexPath) {
            retval.append(validBackwardIndex.indexPath)
        }
        return retval
    }
    
    func calendarOffsetIsAlreadyAtScrollPosition(forIndexPath indexPath:NSIndexPath) -> Bool? {
        var retval: Bool?
        
        // If the scroll is set to animate, and the target content offset is already on the screen, then the didFinishScrollingAnimation
        // delegate will not get called. Once animation is on let's force a scroll so the delegate MUST get caalled
        if let attributes = self.calendarView.layoutAttributesForItemAtIndexPath(indexPath) {
            let layoutOffset: CGFloat
            let calendarOffset: CGFloat
            if direction == .Horizontal {
                layoutOffset = attributes.frame.origin.x
                calendarOffset = calendarView.contentOffset.x
            } else {
                layoutOffset = attributes.frame.origin.y
                calendarOffset = calendarView.contentOffset.y
            }
            if  calendarOffset == layoutOffset || (scrollingMode.pagingIsEnabled() && (indexPath.section ==  currentSectionPage)) {
                retval = true
            } else {
                retval = false
            }
        }
        return retval
    }
    
    func calendarOffsetIsAlreadyAtScrollPosition(forOffset offset:CGPoint) -> Bool? {
        var retval: Bool?
        
        // If the scroll is set to animate, and the target content offset is already on the screen, then the didFinishScrollingAnimation
        // delegate will not get called. Once animation is on let's force a scroll so the delegate MUST get caalled
        
        let theOffset = direction == .Horizontal ? offset.x : offset.y
        let divValue = direction == .Horizontal ? calendarView.frame.width : calendarView.frame.height
        let sectionForOffset = Int(theOffset / divValue)
        let calendarCurrentOffset = direction == .Horizontal ? calendarView.contentOffset.x : calendarView.contentOffset.y
        if
            calendarCurrentOffset == theOffset ||
                (scrollingMode.pagingIsEnabled() && (sectionForOffset ==  currentSectionPage)){
            retval = true
        } else {
            retval = false
        }
        return retval
    }
    
    func firstDayIndexForMonth(date: NSDate) -> Int {
        let firstDayCalValue: Int
        
        switch firstDayOfWeek {
        case .Monday: firstDayCalValue = 6 case .Tuesday: firstDayCalValue = 5 case .Wednesday: firstDayCalValue = 4
        case .Thursday: firstDayCalValue = 10 case .Friday: firstDayCalValue = 9
        case .Saturday: firstDayCalValue = 8 default: firstDayCalValue = 7
        }
        
        var firstWeekdayOfMonthIndex = calendar.component(.Weekday, fromDate: date)
        firstWeekdayOfMonthIndex -= 1 // firstWeekdayOfMonthIndex should be 0-Indexed
        
        return (firstWeekdayOfMonthIndex + firstDayCalValue) % 7 // push it modularly so that we take it back one day so that the first day is Monday instead of Sunday which is the default
    }
    func scrollToHeaderInSection(section:Int, triggerScrollToDateDelegate: Bool = false, withAnimation animation: Bool = true, completionHandler: (()->Void)? = nil)  {
        if registeredHeaderViews.count < 1 { return }
        self.triggerScrollToDateDelegate = triggerScrollToDateDelegate
        let indexPath = NSIndexPath(forItem: 0, inSection: section)
        delayRunOnMainThread(0.0) {
            if let attributes =  self.calendarView.layoutAttributesForSupplementaryElementOfKind(UICollectionElementKindSectionHeader, atIndexPath: indexPath) {
                if let validHandler = completionHandler {
                    self.delayedExecutionClosure.append(validHandler)
                }
                
                let topOfHeader = CGPointMake(attributes.frame.origin.x, attributes.frame.origin.y)
                self.scrollInProgress = true
                
                self.calendarView.setContentOffset(topOfHeader, animated:animation)
                if  !animation {
                    self.scrollViewDidEndScrollingAnimation(self.calendarView)
                    self.scrollInProgress = false
                } else {
                    // If the scroll is set to animate, and the target content offset is already on the screen, then the didFinishScrollingAnimation
                    // delegate will not get called. Once animation is on let's force a scroll so the delegate MUST get caalled
                    if let check = self.calendarOffsetIsAlreadyAtScrollPosition(forOffset: topOfHeader) where check == true {
                        self.scrollViewDidEndScrollingAnimation(self.calendarView)
                        self.scrollInProgress = false
                    }
                }
            }
        }
    }
        
    func reloadData(checkDelegateDataSource check: Bool, withAnchorDate anchorDate: NSDate? = nil, withAnimation animation: Bool = false, completionHandler:(()->Void)? = nil) {
        // Reload the datasource
        if check { reloadDelegateDataSource() }
        var layoutWasUpdated: Bool?
        if layoutNeedsUpdating {
            self.configureChangeOfRows()
            self.layoutNeedsUpdating = false
            layoutWasUpdated = true
        }
        // Reload the data
        self.calendarView.reloadData()
        
        // Restore the selected index paths
        for indexPath in theSelectedIndexPaths { restoreSelectionStateForCellAtIndexPath(indexPath) }
        
        delayRunOnMainThread(0.0) {
            let scrollToDate = {(date: NSDate) -> Void in
                if self.registeredHeaderViews.count < 1 {
                    self.scrollToDate(date, triggerScrollToDateDelegate: false, animateScroll: animation, completionHandler: completionHandler)
                } else {
                    self.scrollToHeaderForDate(date, triggerScrollToDateDelegate: false, withAnimation: animation, completionHandler: completionHandler)
                }
            }
            if let validAnchorDate = anchorDate { // If we have a valid anchor date, this means we want to scroll
                // This scroll should happen after the reload above
                scrollToDate(validAnchorDate)
            } else {
                if layoutWasUpdated == true {
                    // This is a scroll done after a layout reset and dev didnt set an anchor date. If a scroll is in progress, then cancel this one and
                    // allow it to take precedent
                    if !self.scrollInProgress {
                        scrollToDate(self.startOfMonthCache)
                    } else {
                        if let validCompletionHandler = completionHandler { self.delayedExecutionClosure.append(validCompletionHandler) }
                    }
                } else {
                    if let validCompletionHandler = completionHandler {
                        if self.scrollInProgress {
                            self.delayedExecutionClosure.append(validCompletionHandler)
                        } else {
                            validCompletionHandler()
                        }
                    }
                }
            }
        }
    }
    
    func executeDelayedTasks() {
        let tasksToExecute = delayedExecutionClosure
        for aTaskToExecute in tasksToExecute { aTaskToExecute() }
        delayedExecutionClosure.removeAll()
    }
    
    // Only reload the dates if the datasource information has changed
    private func reloadDelegateDataSource() {
        if let
            newDateBoundary = dataSource?.configureCalendar(self) {
            // Jt101 do a check in each var to see if user has bad star/end dates
            let newStartOfMonth = NSDate.startOfMonthForDate(newDateBoundary.startDate, usingCalendar: cachedConfiguration.calendar)
            let newEndOfMonth = NSDate.endOfMonthForDate(newDateBoundary.startDate, usingCalendar: cachedConfiguration.calendar)
            let oldStartOfMonth = NSDate.startOfMonthForDate(cachedConfiguration.startDate, usingCalendar: cachedConfiguration.calendar)
            let oldEndOfMonth = NSDate.endOfMonthForDate(cachedConfiguration.startDate, usingCalendar: cachedConfiguration.calendar)
            
            
            if
                newStartOfMonth != oldStartOfMonth ||
                newEndOfMonth != oldEndOfMonth ||
                newDateBoundary.calendar != cachedConfiguration.calendar ||
                newDateBoundary.numberOfRows != cachedConfiguration.numberOfRows ||
                newDateBoundary.generateInDates != cachedConfiguration.generateInDates ||
                newDateBoundary.generateOutDates != cachedConfiguration.generateOutDates {
                    layoutNeedsUpdating = true
            }
        }
    }
    
    func configureChangeOfRows() {
        let layout = calendarView.collectionViewLayout as! JTAppleCalendarLayoutProtocol
        layout.clearCache()
        
//        monthInfo = setupMonthInfoDataForStartAndEndDate()
        setupMonthInfoAndMap()
        
        // the selected dates and paths will be retained. Ones that are not available on the new layout will be removed.
        var indexPathsToReselect = [NSIndexPath]()
        var newDates = [NSDate]()
        for date in selectedDates {
            // add the index paths of the new layout
            let path = pathsFromDates([date])
            indexPathsToReselect.appendContentsOf(path)
            
            if
                path.count > 0,
                let possibleCounterPartDateIndex = indexPathOfdateCellCounterPart(date, indexPath: path[0], dateOwner: DateOwner.ThisMonth) {
                indexPathsToReselect.append(possibleCounterPartDateIndex)
            }
        }
        
        for path in indexPathsToReselect {
            if let date = dateInfoFromPath(path)?.date { newDates.append(date) }
        }
        
        theSelectedDates = newDates
        theSelectedIndexPaths = indexPathsToReselect
    }
    
    func calendarViewHeaderSizeForSection(section: Int) -> CGSize {
        var retval = CGSizeZero
        if registeredHeaderViews.count > 0 {
            if let
                validDate = dateFromSection(section),
                size = delegate?.calendar(self, sectionHeaderSizeForDate:validDate.dateRange, belongingTo: validDate.month){retval = size }
        }
        return retval
    }
    
    func indexPathOfdateCellCounterPart(date: NSDate, indexPath: NSIndexPath, dateOwner: DateOwner) -> NSIndexPath? {
        if cachedConfiguration.generateInDates == false && cachedConfiguration.generateOutDates == .off { return nil }
        var retval: NSIndexPath?
        if dateOwner != .ThisMonth { // If the cell is anything but this month, then the cell belongs to either a previous of following month
            // Get the indexPath of the counterpartCell
            let counterPathIndex = pathsFromDates([date])
            if counterPathIndex.count > 0 {
                retval = counterPathIndex[0]
            }
        } else { // If the date does belong to this month, then lets find out if it has a counterpart date
            if date >= startOfMonthCache && date <= endOfMonthCache {
                let dayIndex = calendar.components(.Day, fromDate: date).day
                if case 1...13 = dayIndex  { // then check the previous month
                    // get the index path of the last day of the previous month
                    
                    guard let prevMonth = calendar.dateByAddingUnit(.Month, value: -1, toDate: date, options: []) where prevMonth >= startOfMonthCache && prevMonth <= endOfMonthCache else {
                        return retval
                    }
                    
                    guard let lastDayOfPrevMonth = NSDate.endOfMonthForDate(prevMonth, usingCalendar: calendar) else {
                        print("Error generating date in indexPathOfdateCellCounterPart(). Contact the developer on github")
                        return retval
                    }
                    let indexPathOfLastDayOfPreviousMonth = pathsFromDates([lastDayOfPrevMonth])
                    
                    if indexPathOfLastDayOfPreviousMonth.count > 0 {
                        let LastDayIndexPath = indexPathOfLastDayOfPreviousMonth[0]
                        
                        var section = LastDayIndexPath.section
                        var itemIndex = LastDayIndexPath.item + dayIndex
                        
                        
                        // Determine if the sections/item needs to be adjusted
                        let extraSection = itemIndex / numberOfItemsInSection(indexPath.section)
                        let extraIndex = itemIndex % numberOfItemsInSection(indexPath.section)
                        
                        section += extraSection
                        itemIndex = extraIndex
                        
                        let reCalcRapth = NSIndexPath(forItem: itemIndex, inSection: section)
                        
                        // We are going to call a layout attribute function. Make sure the layout is updated. The layout/cell cache will be empty if there was a layout change
                        if (calendarView.collectionViewLayout as! JTAppleCalendarLayout).cellCache.count < 1 {
                            self.calendarView.collectionViewLayout.prepareLayout()
                        }
                        if let attrib = calendarView.collectionViewLayout.layoutAttributesForItemAtIndexPath(reCalcRapth) {
                            if dateInfoFromPath(attrib.indexPath)?.date == date { retval = attrib.indexPath }
                        }
                    } else {
                        print("out of range error in indexPathOfdateCellCounterPart() upper. This should not happen. Contact developer on github")
                    }
                } else if case 26...31 = dayIndex  { // check the following month
                    guard let followingMonth = calendar.dateByAddingUnit(.Month, value: 1, toDate: date, options: []) where followingMonth >= startOfMonthCache && followingMonth <= endOfMonthCache else {
                        return retval
                    }
                    
                    guard let firstDayOfFollowingMonth = NSDate.startOfMonthForDate(followingMonth, usingCalendar: calendar) else {
                        print("Error generating date in indexPathOfdateCellCounterPart(). Contact the developer on github")
                        return retval
                    }
                    let indexPathOfFirstDayOfFollowingMonth = pathsFromDates([firstDayOfFollowingMonth])
                    if indexPathOfFirstDayOfFollowingMonth.count > 0 {
                        let firstDayIndex = indexPathOfFirstDayOfFollowingMonth[0].item
                        let lastDay = NSDate.endOfMonthForDate(date, usingCalendar: calendar)!
                        let lastDayIndex = calendar.components(.Day, fromDate: lastDay).day
                        let x = lastDayIndex - dayIndex
                        let y = firstDayIndex - x - 1
                        
                        if y > -1 {
                            return NSIndexPath(forItem: y, inSection: indexPathOfFirstDayOfFollowingMonth[0].section)
                        }
                    } else {
                        print("out of range error in indexPathOfdateCellCounterPart() lower. This should not happen. Contact developer on github")
                    }
                }
            }
        }
        return retval
    }
    
    func scrollToSection(section: Int, triggerScrollToDateDelegate: Bool = false, animateScroll: Bool = true, completionHandler: (()->Void)?) {
        if scrollInProgress { return }
        if let date = dateInfoFromPath(NSIndexPath(forItem: MAX_NUMBER_OF_DAYS_IN_WEEK - 1, inSection:section))?.date {
            let recalcDate = NSDate.startOfMonthForDate(date, usingCalendar: calendar)!
            self.scrollToDate(recalcDate, triggerScrollToDateDelegate: triggerScrollToDateDelegate, animateScroll: animateScroll, preferredScrollPosition: nil, completionHandler: completionHandler)
        }
    }
    
    func generateNewLayout() -> UICollectionViewLayout {
        let layout: UICollectionViewLayout = JTAppleCalendarLayout(withDelegate: self)
        let conformingProtocolLayout = layout as! JTAppleCalendarLayoutProtocol
        
        conformingProtocolLayout.scrollDirection = direction
        return layout
    }
    
    func setupMonthInfoDataForStartAndEndDate()-> (months: [month], monthMap: [Int:Int]) {
        var months = [month]()
        var monthMap = [Int:Int]()
        if let validConfig = dataSource?.configureCalendar(self) {
            // check if the dates are in correct order
            if validConfig.calendar.compareDate(validConfig.startDate, toDate: validConfig.endDate, toUnitGranularity: NSCalendarUnit.Nanosecond) == NSComparisonResult.OrderedDescending {
                assert(false, "Error, your start date cannot be greater than your end date\n")
                return (months, monthMap)
            }
            
            // Set the new cache
            cachedConfiguration = validConfig
            
            if let
                startMonth = NSDate.startOfMonthForDate(validConfig.startDate, usingCalendar: validConfig.calendar),
                endMonth = NSDate.endOfMonthForDate(validConfig.endDate, usingCalendar: validConfig.calendar) {
                
                startOfMonthCache = startMonth
                endOfMonthCache   = endMonth
                
                // Create the parameters for the date format generator
                let parameters = DateConfigParameters(inCellGeneration: validConfig.generateInDates,
                                                                outCellGeneration: validConfig.generateOutDates,
                                                                numberOfRows: validConfig.numberOfRows,
                                                                startOfMonthCache: startOfMonthCache,
                                                                endOfMonthCache: endOfMonthCache,
                                                                configuredCalendar: validConfig.calendar,
                                                                firstDayOfWeek: firstDayOfWeek)
                
                let generatedData        = dateGenerator.setupMonthInfoDataForStartAndEndDate(parameters)
                months = generatedData.months
                monthMap = generatedData.monthMap
            }
        }
        return (months, monthMap)
    }
    
    func pathsFromDates(dates:[NSDate])-> [NSIndexPath] {
        var returnPaths: [NSIndexPath] = []
//        for date in dates {
//            if  calendar.startOfDayForDate(date) >= startOfMonthCache && calendar.startOfDayForDate(date) <= endOfMonthCache {
//                let periodApart = calendar.components(.Month, fromDate: startOfMonthCache, toDate: date, options: [])
//                let monthSectionIndex = periodApart.month
//                let startSectionIndex = monthSectionIndex * numberOfSectionsPerMonth
//                let sectionIndex = startMonthSectionForSection(startSectionIndex) // Get the section within the month
//                
//                // Get the section Information
//                let currentMonthInfo = monthInfo[sectionIndex]
//                let dayIndex = calendar.components(.Day, fromDate: date).day
//                
//                // Given the following, find the index Path
//                let fdIndex = currentMonthInfo[FIRST_DAY_INDEX]
//                let cellIndex = dayIndex + fdIndex - 1
//                let updatedSection = cellIndex / numberOfItemsPerSection
//                let adjustedSection = sectionIndex + updatedSection
//                let adjustedCellIndex = cellIndex - (numberOfItemsPerSection * (cellIndex / numberOfItemsPerSection))
//                returnPaths.append(NSIndexPath(forItem: adjustedCellIndex, inSection: adjustedSection))
//            }
//        }
        return returnPaths
    }
}

extension JTAppleCalendarView {
    func cellStateFromIndexPath(indexPath: NSIndexPath, withDateInfo info: (date: NSDate, owner: DateOwner)? = nil, cell: JTAppleDayCell? = nil)->CellState {
        let validDateInfo: (date: NSDate, owner: DateOwner)
        if let nonNilDateInfo = info {
            validDateInfo = nonNilDateInfo
        } else {
            guard let newDateInfo = dateInfoFromPath(indexPath) else {
                assert(false, "Error this should not be nil. Contact developer Jay on github by opening a request")
            }
            validDateInfo = newDateInfo
        }
        
        let date = validDateInfo.date
        let dateBelongsTo = validDateInfo.owner
        
        
        let currentDay = calendar.components(.Day, fromDate: date).day
        
        let componentWeekDay = calendar.component(.Weekday, fromDate: date)
        let cellText = String(currentDay)

        let dayOfWeek = DaysOfWeek(rawValue: componentWeekDay)!
        let rangePosition = {()->SelectionRangePosition in
            if self.theSelectedIndexPaths.contains(indexPath) {
                if self.selectedDates.count == 1 { return .Full}
                let left = self.theSelectedIndexPaths.contains(NSIndexPath(forItem: indexPath.item - 1, inSection: indexPath.section))
                let right = self.theSelectedIndexPaths.contains(NSIndexPath(forItem: indexPath.item + 1, inSection: indexPath.section))
                if (left == right) {
                    if left == false { return .Full } else { return .Middle }
                } else {
                    if left == false { return .Left } else { return .Right }
                }
            }
            return .None
        }
        

        let cellState = CellState(
            isSelected: theSelectedIndexPaths.contains(indexPath),
            text: cellText,
            dateBelongsTo: dateBelongsTo,
            date: date,
            day: dayOfWeek,
            row: { return indexPath.item / MAX_NUMBER_OF_DAYS_IN_WEEK },
            column: { return indexPath.item % MAX_NUMBER_OF_DAYS_IN_WEEK },
            dateSection: { return self.dateFromSection(indexPath.section)! },
            selectedPosition: rangePosition,
            cell: {return cell}
        )
        return cellState
    }
    
    func startMonthSectionForSection(aSection: Int)->Int {
        let monthIndexWeAreOn = aSection / numberOfSectionsForMonth(aSection)
        let nextSection = numberOfSectionsForMonth(aSection) * monthIndexWeAreOn
        return nextSection
    }
    
    func batchReloadIndexPaths(indexPaths: [NSIndexPath]) {
        if indexPaths.count < 1 { return }
        UICollectionView.performWithoutAnimation({
            self.calendarView.performBatchUpdates({
                self.calendarView.reloadItemsAtIndexPaths(indexPaths)
                }, completion: nil)  
        })
    }
    
    func addCellToSelectedSetIfUnselected(indexPath: NSIndexPath, date: NSDate) {
        if self.theSelectedIndexPaths.contains(indexPath) == false {
            self.theSelectedIndexPaths.append(indexPath)
            self.theSelectedDates.append(date)
        }
    }
    func deleteCellFromSelectedSetIfSelected(indexPath: NSIndexPath) {
        if let index = self.theSelectedIndexPaths.indexOf(indexPath) {
            self.theSelectedIndexPaths.removeAtIndex(index)
            self.theSelectedDates.removeAtIndex(index)
        }
    }
    func deselectCounterPartCellIndexPath(indexPath: NSIndexPath, date: NSDate, dateOwner: DateOwner) -> NSIndexPath? {
        if let
            counterPartCellIndexPath = indexPathOfdateCellCounterPart(date, indexPath: indexPath, dateOwner: dateOwner) {
            deleteCellFromSelectedSetIfSelected(counterPartCellIndexPath)
            return counterPartCellIndexPath
        }
        return nil
    }
    
    func selectCounterPartCellIndexPathIfExists(indexPath: NSIndexPath, date: NSDate, dateOwner: DateOwner) -> NSIndexPath? {
        if let counterPartCellIndexPath = indexPathOfdateCellCounterPart(date, indexPath: indexPath, dateOwner: dateOwner) {
            let dateComps = calendar.components([.Month, .Day, .Year], fromDate: date)
            guard let counterpartDate = calendar.dateFromComponents(dateComps) else { return nil }
            addCellToSelectedSetIfUnselected(counterPartCellIndexPath, date:counterpartDate)
            return counterPartCellIndexPath
        }
        return nil
    }
    
    func monthInfoForIndex(index: Int) -> month? {
        if let  index = monthMap[index] {
            return monthInfo[index]
        }
        return nil
    }
    
    func dateFromSection(section: Int) -> (dateRange:(start: NSDate, end: NSDate), month: Int)? {
        
        let monthIndex = monthMap[section]!
        let monthData = monthInfo[monthIndex]
        let startIndex = monthData.preDates
        let endIndex = monthData.numberOfDaysInMonth + startIndex - 1
        
        
        let startIndexPath = NSIndexPath(forItem: startIndex, inSection: section)
        let endIndexPath = NSIndexPath(forItem: endIndex, inSection: section)
        
        guard let
            startDate = dateInfoFromPath(startIndexPath)?.date,
            endDate = dateInfoFromPath(endIndexPath)?.date else {
                return nil
        }
            
        if let monthDate = calendar.dateByAddingUnit(.Month, value: monthIndex, toDate: startDateCache, options: []) {
            let monthNumber = calendar.components(.Month, fromDate: monthDate)
            return ((startDate, endDate), monthNumber.month)
        }
        
        return nil
    }
    
    
    
    func dateInfoFromPath(indexPath: NSIndexPath)-> (date: NSDate, owner: DateOwner)? { // Returns nil if date is out of scope
        guard let monthIndex = monthMap[indexPath.section] else {
            return nil
        }
        
        let monthData = monthInfo[monthIndex]
        let offSet: Int
        var numberOfDaysToAddToOffset: Int = 0
        
        switch monthData.sectionIndexMaps[indexPath.section]! {
        case 0:
            offSet = monthData.preDates
        default:
            offSet = 0
            let currentSectionIndexMap = monthData.sectionIndexMaps[indexPath.section]!
            
            numberOfDaysToAddToOffset = monthData.sections[0..<currentSectionIndexMap].reduce(0, combine: +)
            numberOfDaysToAddToOffset -= monthData.preDates
        }
        
        var dayIndex = 0
        var dateOwner: DateOwner = .ThisMonth
        let date: NSDate?
        let dateComponents = NSDateComponents()
        
        if indexPath.item >= offSet && indexPath.item + numberOfDaysToAddToOffset < monthData.numberOfDaysInMonth + offSet {
            // This is a month date
            dayIndex = monthData.startIndex + indexPath.item - offSet + numberOfDaysToAddToOffset
            dateComponents.day = dayIndex
            date = calendar.dateByAddingComponents(dateComponents, toDate: startOfMonthCache, options: [])
            dateOwner = .ThisMonth
        } else if indexPath.item < offSet {
            // This is a preDate
            dayIndex = indexPath.item - offSet  + monthData.startIndex
            dateComponents.day = dayIndex
            date = calendar.dateByAddingComponents(dateComponents, toDate: startOfMonthCache, options: [])
            print(dayIndex)
            print(date)
            if date < startOfMonthCache {
                dateOwner = .PreviousMonthOutsideBoundary
            } else {
                dateOwner = .PreviousMonthWithinBoundary
            }
        } else {
            // This is a postDate
            dayIndex =  monthData.startIndex - offSet + indexPath.item + numberOfDaysToAddToOffset
            dateComponents.day = dayIndex
            date = calendar.dateByAddingComponents(dateComponents, toDate: startOfMonthCache, options: [])
            if date > endOfMonthCache {
                dateOwner = .FollowingMonthOutsideBoundary
            } else {
                dateOwner = .FollowingMonthWithinBoundary
            }
        }
        
        guard let validDate = date else {
            return nil
        }
        
        return (validDate, dateOwner)
    }
}

extension JTAppleCalendarView: JTAppleCalendarDelegateProtocol {
    func cachedDate() -> (start: NSDate, end: NSDate, calendar: NSCalendar) { return (start: cachedConfiguration.startDate, end: cachedConfiguration.endDate, calendar: cachedConfiguration.calendar) }
    func numberOfRows() -> Int {return cachedConfiguration.numberOfRows}
//    func numberOfColumns() -> Int { return MAX_NUMBER_OF_DAYS_IN_WEEK }
    func numberOfsections(forMonth section:Int) -> Int { return numberOfSectionsForMonth(section) }
    func numberOfMonthsInCalendar() -> Int { return numberOfMonths }
    
    func numberOfPreDatesForMonth(month: NSDate) -> Int { return firstDayIndexForMonth(month) }
    func numberOfPostDatesForMonth(month: NSDate) -> Int { return firstDayIndexForMonth(month) }
    
    func preDatesAreGenerated() -> Bool { return cachedConfiguration.generateInDates }
    func postDatesAreGenerated() -> OutDateCellGeneration { return cachedConfiguration.generateOutDates }

    func referenceSizeForHeaderInSection(section: Int) -> CGSize {
        if registeredHeaderViews.count < 1 { return CGSizeZero }
        return calendarViewHeaderSizeForSection(section)
    }
    
    func rowsAreStatic() -> Bool {
        return cachedConfiguration.generateInDates == true && cachedConfiguration.generateOutDates == .tillEndOfGrid
    }
}
