;; Equipment Lease Automation Contract
;; Track equipment usage, calculate lease payments, and manage end-of-lease procedures

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_INSUFFICIENT_BALANCE (err u103))
(define-constant ERR_INVALID_STATUS (err u104))
(define-constant ERR_LEASE_ACTIVE (err u105))
(define-constant ERR_LEASE_EXPIRED (err u106))
(define-constant ERR_EQUIPMENT_UNAVAILABLE (err u107))
(define-constant ERR_INVALID_DURATION (err u108))
(define-constant ERR_MAINTENANCE_REQUIRED (err u109))
(define-constant ERR_DAMAGE_DETECTED (err u110))

;; Equipment Status Constants
(define-constant EQUIPMENT_AVAILABLE u1)
(define-constant EQUIPMENT_LEASED u2)
(define-constant EQUIPMENT_MAINTENANCE u3)
(define-constant EQUIPMENT_DAMAGED u4)
(define-constant EQUIPMENT_RETIRED u5)

;; Lease Status Constants
(define-constant LEASE_ACTIVE u1)
(define-constant LEASE_COMPLETED u2)
(define-constant LEASE_CANCELLED u3)
(define-constant LEASE_OVERDUE u4)
(define-constant LEASE_DISPUTED u5)

;; Pricing Models
(define-constant HOURLY_PRICING u1)
(define-constant DAILY_PRICING u2)
(define-constant WEEKLY_PRICING u3)
(define-constant MONTHLY_PRICING u4)
(define-constant USAGE_BASED u5)

;; Data Variables
(define-data-var next-equipment-id uint u1)
(define-data-var next-lease-id uint u1)
(define-data-var platform-fee uint u200) ;; 2% fee (200/10000)
(define-data-var admin principal CONTRACT_OWNER)
(define-data-var total-revenue uint u0)
(define-data-var maintenance-fund uint u0)

;; Data Maps
(define-map equipment-registry
  { equipment-id: uint }
  {
    owner: principal,
    equipment-name: (string-ascii 100),
    category: (string-ascii 50),
    description: (string-ascii 300),
    specifications: (string-ascii 500),
    hourly-rate: uint,
    daily-rate: uint,
    weekly-rate: uint,
    monthly-rate: uint,
    usage-rate: uint,
    deposit-amount: uint,
    location: (string-ascii 100),
    status: uint,
    total-usage-hours: uint,
    last-maintenance: uint,
    next-maintenance: uint,
    condition-score: uint,
    created-at: uint
  }
)

(define-map lease-agreements
  { lease-id: uint }
  {
    equipment-id: uint,
    lessee: principal,
    lessor: principal,
    start-date: uint,
    end-date: uint,
    pricing-model: uint,
    rate: uint,
    deposit-paid: uint,
    usage-hours: uint,
    total-cost: uint,
    amount-paid: uint,
    status: uint,
    created-at: uint
  }
)

(define-map usage-tracking
  { tracking-id: uint }
  {
    equipment-id: uint,
    lease-id: uint,
    usage-start: uint,
    usage-end: uint,
    hours-used: uint,
    location: (string-ascii 100),
    fuel-consumed: uint,
    performance-metrics: (string-ascii 200),
    recorded-at: uint
  }
)

(define-map billing-records
  { billing-id: uint }
  {
    lease-id: uint,
    equipment-id: uint,
    billing-period-start: uint,
    billing-period-end: uint,
    usage-charges: uint,
    maintenance-fees: uint,
    damage-charges: uint,
    platform-fee: uint,
    total-amount: uint,
    payment-status: (string-ascii 20),
    generated-at: uint,
    paid-at: (optional uint)
  }
)

(define-map maintenance-records
  { maintenance-id: uint }
  {
    equipment-id: uint,
    maintenance-type: (string-ascii 50),
    description: (string-ascii 300),
    cost: uint,
    performed-by: principal,
    scheduled-date: uint,
    completed-date: (optional uint),
    next-scheduled: uint,
    status: (string-ascii 20)
  }
)

(define-map equipment-performance
  { equipment-id: uint, period: uint }
  {
    total-hours: uint,
    utilization-rate: uint,
    revenue-generated: uint,
    maintenance-cost: uint,
    efficiency-score: uint,
    downtime-hours: uint
  }
)

(define-map user-profiles
  { user: principal }
  {
    reputation-score: uint,
    total-leases: uint,
    completed-leases: uint,
    total-spent: uint,
    total-earned: uint,
    late-payment-count: uint,
    damage-incidents: uint
  }
)

;; Private Functions

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee)) u10000)
)

(define-private (is-equipment-owner (equipment-id uint) (user principal))
  (match (map-get? equipment-registry { equipment-id: equipment-id })
    equipment (is-eq user (get owner equipment))
    false
  )
)

(define-private (calculate-lease-cost (equipment-id uint) (pricing-model uint) (duration uint) (usage-hours uint))
  (let (
    (equipment (unwrap-panic (map-get? equipment-registry { equipment-id: equipment-id })))
  )
    (if (is-eq pricing-model HOURLY_PRICING)
      (* (get hourly-rate equipment) usage-hours)
      (if (is-eq pricing-model DAILY_PRICING)
        (* (get daily-rate equipment) duration)
        (if (is-eq pricing-model WEEKLY_PRICING)
          (* (get weekly-rate equipment) (/ duration u7))
          (if (is-eq pricing-model MONTHLY_PRICING)
            (* (get monthly-rate equipment) (/ duration u30))
            (* (get usage-rate equipment) usage-hours)
          )
        )
      )
    )
  )
)

(define-private (update-user-profile (user principal) (amount uint) (is-payment bool))
  (let (
    (current-profile (default-to
      { reputation-score: u100, total-leases: u0, completed-leases: u0, total-spent: u0, total-earned: u0, late-payment-count: u0, damage-incidents: u0 }
      (map-get? user-profiles { user: user })
    ))
  )
    (map-set user-profiles
      { user: user }
      {
        reputation-score: (get reputation-score current-profile),
        total-leases: (+ (get total-leases current-profile) u1),
        completed-leases: (get completed-leases current-profile),
        total-spent: (if is-payment (+ (get total-spent current-profile) amount) (get total-spent current-profile)),
        total-earned: (if (not is-payment) (+ (get total-earned current-profile) amount) (get total-earned current-profile)),
        late-payment-count: (get late-payment-count current-profile),
        damage-incidents: (get damage-incidents current-profile)
      }
    )
  )
)

;; Public Functions

;; Register new equipment
(define-public (register-equipment
  (equipment-name (string-ascii 100))
  (category (string-ascii 50))
  (description (string-ascii 300))
  (specifications (string-ascii 500))
  (hourly-rate uint)
  (daily-rate uint)
  (weekly-rate uint)
  (monthly-rate uint)
  (usage-rate uint)
  (deposit-amount uint)
  (location (string-ascii 100))
)
  (let (
    (equipment-id (var-get next-equipment-id))
  )
    (asserts! (> hourly-rate u0) ERR_INVALID_AMOUNT)
    (asserts! (> deposit-amount u0) ERR_INVALID_AMOUNT)
    
    ;; Register equipment
    (map-set equipment-registry
      { equipment-id: equipment-id }
      {
        owner: tx-sender,
        equipment-name: equipment-name,
        category: category,
        description: description,
        specifications: specifications,
        hourly-rate: hourly-rate,
        daily-rate: daily-rate,
        weekly-rate: weekly-rate,
        monthly-rate: monthly-rate,
        usage-rate: usage-rate,
        deposit-amount: deposit-amount,
        location: location,
        status: EQUIPMENT_AVAILABLE,
        total-usage-hours: u0,
        last-maintenance: block-height,
        next-maintenance: (+ block-height u4320), ;; ~30 days
        condition-score: u100,
        created-at: block-height
      }
    )
    
    (var-set next-equipment-id (+ equipment-id u1))
    (ok equipment-id)
  )
)

;; Create lease agreement
(define-public (create-lease
  (equipment-id uint)
  (duration uint)
  (pricing-model uint)
)
  (let (
    (equipment (unwrap! (map-get? equipment-registry { equipment-id: equipment-id }) ERR_NOT_FOUND))
    (lease-id (var-get next-lease-id))
    (end-date (+ block-height duration))
  )
    (asserts! (is-eq (get status equipment) EQUIPMENT_AVAILABLE) ERR_EQUIPMENT_UNAVAILABLE)
    (asserts! (> duration u0) ERR_INVALID_DURATION)
    (asserts! (not (is-eq tx-sender (get owner equipment))) ERR_UNAUTHORIZED)
    (asserts! (<= pricing-model USAGE_BASED) ERR_INVALID_AMOUNT)
    
    ;; Create lease agreement
    (map-set lease-agreements
      { lease-id: lease-id }
      {
        equipment-id: equipment-id,
        lessee: tx-sender,
        lessor: (get owner equipment),
        start-date: block-height,
        end-date: end-date,
        pricing-model: pricing-model,
        rate: (get hourly-rate equipment),
        deposit-paid: (get deposit-amount equipment),
        usage-hours: u0,
        total-cost: u0,
        amount-paid: u0,
        status: LEASE_ACTIVE,
        created-at: block-height
      }
    )
    
    ;; Update equipment status
    (map-set equipment-registry
      { equipment-id: equipment-id }
      (merge equipment { status: EQUIPMENT_LEASED })
    )
    
    ;; Update user profile
    (update-user-profile tx-sender u0 true)
    
    (var-set next-lease-id (+ lease-id u1))
    (ok lease-id)
  )
)

;; Record equipment usage
(define-public (record-usage
  (equipment-id uint)
  (lease-id uint)
  (usage-start uint)
  (usage-end uint)
  (location (string-ascii 100))
  (fuel-consumed uint)
  (performance-metrics (string-ascii 200))
)
  (let (
    (lease (unwrap! (map-get? lease-agreements { lease-id: lease-id }) ERR_NOT_FOUND))
    (equipment (unwrap! (map-get? equipment-registry { equipment-id: equipment-id }) ERR_NOT_FOUND))
    (hours-used (if (> usage-end usage-start) (- usage-end usage-start) u0))
    (tracking-id (+ lease-id equipment-id)) ;; Simple tracking ID generation
  )
    (asserts! (is-eq tx-sender (get lessee lease)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status lease) LEASE_ACTIVE) ERR_LEASE_EXPIRED)
    (asserts! (is-eq equipment-id (get equipment-id lease)) ERR_NOT_FOUND)
    (asserts! (> hours-used u0) ERR_INVALID_AMOUNT)
    
    ;; Record usage
    (map-set usage-tracking
      { tracking-id: tracking-id }
      {
        equipment-id: equipment-id,
        lease-id: lease-id,
        usage-start: usage-start,
        usage-end: usage-end,
        hours-used: hours-used,
        location: location,
        fuel-consumed: fuel-consumed,
        performance-metrics: performance-metrics,
        recorded-at: block-height
      }
    )
    
    ;; Update lease usage
    (map-set lease-agreements
      { lease-id: lease-id }
      (merge lease { usage-hours: (+ (get usage-hours lease) hours-used) })
    )
    
    ;; Update equipment usage
    (map-set equipment-registry
      { equipment-id: equipment-id }
      (merge equipment { total-usage-hours: (+ (get total-usage-hours equipment) hours-used) })
    )
    
    (ok hours-used)
  )
)

;; Generate billing for lease period
(define-public (generate-billing (lease-id uint) (period-start uint) (period-end uint))
  (let (
    (lease (unwrap! (map-get? lease-agreements { lease-id: lease-id }) ERR_NOT_FOUND))
    (equipment (unwrap! (map-get? equipment-registry { equipment-id: (get equipment-id lease) }) ERR_NOT_FOUND))
    (billing-id (+ lease-id period-start)) ;; Simple billing ID generation
    (usage-charges (calculate-lease-cost (get equipment-id lease) (get pricing-model lease) (- period-end period-start) (get usage-hours lease)))
    (maintenance-fees (/ (* usage-charges u5) u100)) ;; 5% maintenance fee
    (fee-amount (calculate-platform-fee usage-charges))
    (total-amount (+ usage-charges maintenance-fees fee-amount))
  )
    (asserts! (or (is-eq tx-sender (get lessor lease)) (is-eq tx-sender (var-get admin))) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status lease) LEASE_ACTIVE) ERR_LEASE_EXPIRED)
    (asserts! (< period-start period-end) ERR_INVALID_AMOUNT)
    
    ;; Generate billing record
    (map-set billing-records
      { billing-id: billing-id }
      {
        lease-id: lease-id,
        equipment-id: (get equipment-id lease),
        billing-period-start: period-start,
        billing-period-end: period-end,
        usage-charges: usage-charges,
        maintenance-fees: maintenance-fees,
        damage-charges: u0,
        platform-fee: fee-amount,
        total-amount: total-amount,
        payment-status: "pending",
        generated-at: block-height,
        paid-at: none
      }
    )
    
    (ok total-amount)
  )
)

;; Process payment for billing
(define-public (process-payment (billing-id uint) (amount uint))
  (let (
    (billing (unwrap! (map-get? billing-records { billing-id: billing-id }) ERR_NOT_FOUND))
    (lease (unwrap! (map-get? lease-agreements { lease-id: (get lease-id billing) }) ERR_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (get lessee lease)) ERR_UNAUTHORIZED)
    (asserts! (>= amount (get total-amount billing)) ERR_INSUFFICIENT_BALANCE)
    
    ;; Update billing record
    (map-set billing-records
      { billing-id: billing-id }
      (merge billing {
        payment-status: "paid",
        paid-at: (some block-height)
      })
    )
    
    ;; Update lease payment
    (map-set lease-agreements
      { lease-id: (get lease-id billing) }
      (merge lease {
        amount-paid: (+ (get amount-paid lease) amount),
        total-cost: (+ (get total-cost lease) (get total-amount billing))
      })
    )
    
    ;; Update platform revenue
    (var-set total-revenue (+ (var-get total-revenue) (get platform-fee billing)))
    (var-set maintenance-fund (+ (var-get maintenance-fund) (get maintenance-fees billing)))
    
    ;; Update user profile
    (update-user-profile tx-sender amount true)
    (update-user-profile (get lessor lease) (- amount (get platform-fee billing)) false)
    
    (ok true)
  )
)

;; Complete lease and return equipment
(define-public (complete-lease (lease-id uint) (condition-score uint) (damage-charges uint))
  (let (
    (lease (unwrap! (map-get? lease-agreements { lease-id: lease-id }) ERR_NOT_FOUND))
    (equipment (unwrap! (map-get? equipment-registry { equipment-id: (get equipment-id lease) }) ERR_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (get lessor lease)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status lease) LEASE_ACTIVE) ERR_INVALID_STATUS)
    (asserts! (<= condition-score u100) ERR_INVALID_AMOUNT)
    
    ;; Update lease status
    (map-set lease-agreements
      { lease-id: lease-id }
      (merge lease { status: LEASE_COMPLETED })
    )
    
    ;; Update equipment status and condition
    (map-set equipment-registry
      { equipment-id: (get equipment-id lease) }
      (merge equipment {
        status: EQUIPMENT_AVAILABLE,
        condition-score: condition-score
      })
    )
    
    ;; Update user profiles
    (let (
      (lessee-profile (default-to
        { reputation-score: u100, total-leases: u0, completed-leases: u0, total-spent: u0, total-earned: u0, late-payment-count: u0, damage-incidents: u0 }
        (map-get? user-profiles { user: (get lessee lease) })
      ))
    )
      (map-set user-profiles
        { user: (get lessee lease) }
        (merge lessee-profile {
          completed-leases: (+ (get completed-leases lessee-profile) u1),
          damage-incidents: (if (> damage-charges u0) (+ (get damage-incidents lessee-profile) u1) (get damage-incidents lessee-profile))
        })
      )
    )
    
    (ok true)
  )
)

;; Schedule maintenance
(define-public (schedule-maintenance
  (equipment-id uint)
  (maintenance-type (string-ascii 50))
  (description (string-ascii 300))
  (estimated-cost uint)
  (scheduled-date uint)
)
  (let (
    (equipment (unwrap! (map-get? equipment-registry { equipment-id: equipment-id }) ERR_NOT_FOUND))
    (maintenance-id (+ equipment-id scheduled-date)) ;; Simple maintenance ID generation
  )
    (asserts! (is-equipment-owner equipment-id tx-sender) ERR_UNAUTHORIZED)
    (asserts! (> scheduled-date block-height) ERR_INVALID_AMOUNT)
    
    ;; Schedule maintenance
    (map-set maintenance-records
      { maintenance-id: maintenance-id }
      {
        equipment-id: equipment-id,
        maintenance-type: maintenance-type,
        description: description,
        cost: estimated-cost,
        performed-by: tx-sender,
        scheduled-date: scheduled-date,
        completed-date: none,
        next-scheduled: (+ scheduled-date u4320), ;; ~30 days after
        status: "scheduled"
      }
    )
    
    (ok maintenance-id)
  )
)

;; Read-only Functions

(define-read-only (get-equipment (equipment-id uint))
  (map-get? equipment-registry { equipment-id: equipment-id })
)

(define-read-only (get-lease (lease-id uint))
  (map-get? lease-agreements { lease-id: lease-id })
)

(define-read-only (get-usage-record (tracking-id uint))
  (map-get? usage-tracking { tracking-id: tracking-id })
)

(define-read-only (get-billing-record (billing-id uint))
  (map-get? billing-records { billing-id: billing-id })
)

(define-read-only (get-maintenance-record (maintenance-id uint))
  (map-get? maintenance-records { maintenance-id: maintenance-id })
)

(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles { user: user })
)

(define-read-only (get-equipment-performance (equipment-id uint) (period uint))
  (map-get? equipment-performance { equipment-id: equipment-id, period: period })
)

(define-read-only (get-platform-stats)
  {
    total-equipment: (- (var-get next-equipment-id) u1),
    total-leases: (- (var-get next-lease-id) u1),
    total-revenue: (var-get total-revenue),
    maintenance-fund: (var-get maintenance-fund),
    platform-fee: (var-get platform-fee)
  }
)

;; Admin Functions

(define-public (set-platform-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR_UNAUTHORIZED)
    (asserts! (<= new-fee u1000) ERR_INVALID_AMOUNT) ;; Max 10% fee
    (var-set platform-fee new-fee)
    (ok true)
  )
)

(define-public (emergency-stop-lease (lease-id uint))
  (let (
    (lease (unwrap! (map-get? lease-agreements { lease-id: lease-id }) ERR_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (var-get admin)) ERR_UNAUTHORIZED)
    
    (map-set lease-agreements
      { lease-id: lease-id }
      (merge lease { status: LEASE_CANCELLED })
    )
    
    (ok true)
  )
)

(define-public (withdraw-maintenance-fund (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR_UNAUTHORIZED)
    (asserts! (<= amount (var-get maintenance-fund)) ERR_INSUFFICIENT_BALANCE)
    (var-set maintenance-fund (- (var-get maintenance-fund) amount))
    (ok true)
  )
)
