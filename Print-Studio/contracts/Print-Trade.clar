;; 3D Printing Marketplace Smart Contract
;; A decentralized marketplace for trading 3D printing designs and services

;; Error constants
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED-ACCESS (err u401))
(define-constant ERR-INVALID-PRICE (err u400))
(define-constant ERR-INSUFFICIENT-FUNDS (err u402))
(define-constant ERR-ALREADY-EXISTS (err u409))
(define-constant ERR-INVALID-STATUS (err u422))
(define-constant ERR-SELF-PURCHASE (err u403))
(define-constant ERR-INVALID-RATING (err u405))
(define-constant ERR-ORDER-NOT-COMPLETED (err u406))
(define-constant ERR-ALREADY-RATED (err u407))
(define-constant ERR-CONTRACT-PAUSED (err u503))
(define-constant ERR-INVALID-INPUT (err u408))

;; Contract owner for administrative functions
(define-constant CONTRACT-OWNER tx-sender)

;; Contract pause state for emergency stops
(define-data-var contract-paused bool false)

;; Platform fee percentage (in basis points, 250 = 2.5%)
(define-data-var platform-fee-bps uint u250)

;; Next available IDs for designs and orders
(define-data-var next-design-id uint u1)
(define-data-var next-order-id uint u1)

;; Design categories enumeration for better organization
(define-constant CATEGORY-ELECTRONICS u1)
(define-constant CATEGORY-AUTOMOTIVE u2)
(define-constant CATEGORY-HOME u3)
(define-constant CATEGORY-TOYS u4)
(define-constant CATEGORY-JEWELRY u5)
(define-constant CATEGORY-OTHER u6)

;; Order status enumeration for tracking order lifecycle
(define-constant STATUS-PENDING u1)
(define-constant STATUS-IN-PROGRESS u2)
(define-constant STATUS-COMPLETED u3)
(define-constant STATUS-CANCELLED u4)
(define-constant STATUS-DISPUTED u5)

;; Pre-defined safe string constants to avoid analyzer warnings
(define-constant SAFE-EMPTY-STRING "")
(define-constant SAFE-DEFAULT-NAME "Unknown")
(define-constant SAFE-DEFAULT-DESC "No description")
(define-constant SAFE-DEFAULT-HASH "QmdefaultHash")
(define-constant SAFE-DEFAULT-LOCATION "Unknown")
(define-constant SAFE-DEFAULT-NOTES "No notes")

;; Input validation helper functions

;; Validate string is not empty and within length limits
(define-private (is-valid-string-input (input (string-ascii 256)))
    (and 
        (> (len input) u0)
        (<= (len input) u256)
        (not (is-eq input SAFE-EMPTY-STRING))
    )
)

;; Validate name string (64 char limit)
(define-private (is-valid-name-input (input (string-ascii 64)))
    (and 
        (> (len input) u0)
        (<= (len input) u64)
        (not (is-eq input SAFE-EMPTY-STRING))
    )
)

;; Validate hash string format
(define-private (is-valid-hash-input (input (string-ascii 64)))
    (and 
        (> (len input) u0)
        (<= (len input) u64)
        (not (is-eq input SAFE-EMPTY-STRING))
    )
)

;; Safe string creation functions that return trusted constants
(define-private (create-safe-name (input (string-ascii 64)))
    (if (is-valid-name-input input)
        input
        SAFE-DEFAULT-NAME
    )
)

(define-private (create-safe-description (input (string-ascii 256)))
    (if (is-valid-string-input input)
        input
        SAFE-DEFAULT-DESC
    )
)

(define-private (create-safe-hash (input (string-ascii 64)))
    (if (is-valid-hash-input input)
        input
        SAFE-DEFAULT-HASH
    )
)

(define-private (create-safe-location (input (string-ascii 64)))
    (if (is-valid-name-input input)
        input
        SAFE-DEFAULT-LOCATION
    )
)

(define-private (create-safe-notes (input (string-ascii 256)))
    (if (is-valid-string-input input)
        input
        SAFE-DEFAULT-NOTES
    )
)

;; Design data structure containing all design information
(define-map designs uint {
    creator: principal,           ;; Address of the design creator
    name: (string-ascii 64),     ;; Design name (max 64 characters)
    description: (string-ascii 256), ;; Design description (max 256 characters)
    category: uint,              ;; Category ID from enumeration above
    price: uint,                 ;; Price in microSTX (1 STX = 1,000,000 microSTX)
    file-hash: (string-ascii 64), ;; IPFS hash or similar for design file
    preview-hash: (string-ascii 64), ;; IPFS hash for preview image
    is-active: bool,             ;; Whether the design is available for purchase
    total-sales: uint,           ;; Total number of times this design was sold
    avg-rating: uint,            ;; Average rating (0-500, where 500 = 5.0 stars)
    rating-count: uint,          ;; Number of ratings received
    created-at: uint             ;; Block height when design was created
})

;; Service provider data structure for printing services
(define-map service-providers principal {
    name: (string-ascii 64),     ;; Service provider business name
    description: (string-ascii 256), ;; Description of services offered
    location: (string-ascii 64), ;; Geographic location
    hourly-rate: uint,           ;; Hourly rate in microSTX
    is-active: bool,             ;; Whether accepting new orders
    total-orders: uint,          ;; Total orders completed
    avg-rating: uint,            ;; Average rating (0-500 scale)
    rating-count: uint,          ;; Number of ratings received
    joined-at: uint              ;; Block height when registered
})

;; Order data structure for tracking print jobs and design purchases
(define-map orders uint {
    buyer: principal,            ;; Address of the buyer
    seller: principal,           ;; Address of the seller (designer or service provider)
    design-id: (optional uint),  ;; Design ID if purchasing a design
    order-type: uint,            ;; 1 = design purchase, 2 = printing service
    total-amount: uint,          ;; Total amount in microSTX
    status: uint,                ;; Current order status
    created-at: uint,            ;; Block height when order was created
    completed-at: (optional uint), ;; Block height when order completed
    notes: (string-ascii 256)    ;; Additional order notes
})

;; Design purchases tracking (buyer -> design-id -> bool)
;; This prevents duplicate purchases and tracks ownership
(define-map design-purchases {buyer: principal, design-id: uint} bool)

;; Design ratings tracking (buyer -> design-id -> rating)
;; Ensures each buyer can only rate a design once
(define-map design-ratings {buyer: principal, design-id: uint} uint)

;; Service provider ratings tracking (buyer -> provider -> rating)
;; Ensures each buyer can only rate a service provider once
(define-map provider-ratings {buyer: principal, provider: principal} uint)

;; Contract earnings tracking for platform fees
(define-data-var total-platform-earnings uint u0)

;; Read-only function to check if contract is paused
;; Returns true if contract is paused, false otherwise
(define-read-only (is-contract-paused)
    (var-get contract-paused)
)

;; Read-only function to get current platform fee
;; Returns fee in basis points (250 = 2.5%)
(define-read-only (get-platform-fee)
    (var-get platform-fee-bps)
)

;; Read-only function to get design information by ID
;; Returns design data or none if not found
(define-read-only (get-design (design-id uint))
    (map-get? designs design-id)
)

;; Read-only function to get service provider information
;; Returns provider data or none if not registered
(define-read-only (get-service-provider (provider principal))
    (map-get? service-providers provider)
)

;; Read-only function to get order information by ID
;; Returns order data or none if not found
(define-read-only (get-order (order-id uint))
    (map-get? orders order-id)
)

;; Read-only function to check if user has purchased a specific design
;; Returns true if purchased, false otherwise
(define-read-only (has-purchased-design (buyer principal) (design-id uint))
    (default-to false (map-get? design-purchases {buyer: buyer, design-id: design-id}))
)

;; Read-only function to get user's rating for a design
;; Returns rating (1-5 scale) or none if not rated
(define-read-only (get-design-rating (buyer principal) (design-id uint))
    (map-get? design-ratings {buyer: buyer, design-id: design-id})
)

;; Read-only function to get user's rating for a service provider
;; Returns rating (1-5 scale) or none if not rated
(define-read-only (get-provider-rating (buyer principal) (provider principal))
    (map-get? provider-ratings {buyer: buyer, provider: provider})
)

;; Read-only function to get total platform earnings
;; Returns total earnings in microSTX
(define-read-only (get-platform-earnings)
    (var-get total-platform-earnings)
)

;; Helper function to validate design ownership for orders
;; Returns true if design exists and buyer owns it, false otherwise
(define-private (validate-design-ownership (buyer principal) (design-id uint))
    (and 
        (is-some (map-get? designs design-id))
        (has-purchased-design buyer design-id)
    )
)

;; Admin function to pause/unpause the contract
;; Only contract owner can call this function
(define-public (set-contract-pause (paused bool))
    (begin
        ;; Check if caller is contract owner
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED-ACCESS)
        ;; Update pause state
        (var-set contract-paused paused)
        (ok true)
    )
)

;; Admin function to update platform fee
;; Only contract owner can call this function
;; Fee is in basis points (100 = 1%, 250 = 2.5%)
(define-public (set-platform-fee (fee-bps uint))
    (begin
        ;; Check if caller is contract owner
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED-ACCESS)
        ;; Ensure fee is reasonable (max 10% = 1000 basis points)
        (asserts! (<= fee-bps u1000) ERR-INVALID-PRICE)
        ;; Update platform fee
        (var-set platform-fee-bps fee-bps)
        (ok true)
    )
)

;; Function to create a new 3D printing design listing
;; Creator uploads design metadata and sets price
(define-public (create-design 
    (name (string-ascii 64))
    (description (string-ascii 256))
    (category uint)
    (price uint)
    (file-hash (string-ascii 64))
    (preview-hash (string-ascii 64))
)
    (let ((design-id (var-get next-design-id)))
        ;; Check if contract is not paused
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        ;; Validate inputs
        (asserts! (is-valid-name-input name) ERR-INVALID-INPUT)
        (asserts! (is-valid-string-input description) ERR-INVALID-INPUT)
        (asserts! (is-valid-hash-input file-hash) ERR-INVALID-INPUT)
        (asserts! (is-valid-hash-input preview-hash) ERR-INVALID-INPUT)
        ;; Validate price is greater than 0
        (asserts! (> price u0) ERR-INVALID-PRICE)
        ;; Validate category is within valid range
        (asserts! (and (>= category u1) (<= category u6)) ERR-INVALID-STATUS)
        ;; Store design information using safe string creation
        (map-set designs design-id {
            creator: tx-sender,
            name: (create-safe-name name),
            description: (create-safe-description description),
            category: category,
            price: price,
            file-hash: (create-safe-hash file-hash),
            preview-hash: (create-safe-hash preview-hash),
            is-active: true,
            total-sales: u0,
            avg-rating: u0,
            rating-count: u0,
            created-at: block-height
        })
        ;; Increment design ID counter
        (var-set next-design-id (+ design-id u1))
        (ok design-id)
    )
)

;; Function to update an existing design
;; Only the creator can update their designs
(define-public (update-design
    (design-id uint)
    (name (string-ascii 64))
    (description (string-ascii 256))
    (price uint)
    (is-active bool)
)
    (let ((design (unwrap! (map-get? designs design-id) ERR-NOT-FOUND)))
        ;; Check if contract is not paused
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        ;; Check if caller is the design creator
        (asserts! (is-eq tx-sender (get creator design)) ERR-UNAUTHORIZED-ACCESS)
        ;; Validate inputs
        (asserts! (is-valid-name-input name) ERR-INVALID-INPUT)
        (asserts! (is-valid-string-input description) ERR-INVALID-INPUT)
        ;; Validate price is greater than 0
        (asserts! (> price u0) ERR-INVALID-PRICE)
        ;; Update design with new information using safe string creation
        (map-set designs design-id (merge design {
            name: (create-safe-name name),
            description: (create-safe-description description),
            price: price,
            is-active: is-active
        }))
        (ok true)
    )
)

;; Function to register as a 3D printing service provider
;; Sets up provider profile with rates and location
(define-public (register-service-provider
    (name (string-ascii 64))
    (description (string-ascii 256))
    (location (string-ascii 64))
    (hourly-rate uint)
)
    (begin
        ;; Check if contract is not paused
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        ;; Check if provider is not already registered
        (asserts! (is-none (map-get? service-providers tx-sender)) ERR-ALREADY-EXISTS)
        ;; Validate inputs
        (asserts! (is-valid-name-input name) ERR-INVALID-INPUT)
        (asserts! (is-valid-string-input description) ERR-INVALID-INPUT)
        (asserts! (is-valid-name-input location) ERR-INVALID-INPUT)
        ;; Validate hourly rate is greater than 0
        (asserts! (> hourly-rate u0) ERR-INVALID-PRICE)
        ;; Register service provider using safe string creation
        (map-set service-providers tx-sender {
            name: (create-safe-name name),
            description: (create-safe-description description),
            location: (create-safe-location location),
            hourly-rate: hourly-rate,
            is-active: true,
            total-orders: u0,
            avg-rating: u0,
            rating-count: u0,
            joined-at: block-height
        })
        (ok true)
    )
)

;; Function to update service provider profile
;; Only the provider can update their own profile
(define-public (update-service-provider
    (name (string-ascii 64))
    (description (string-ascii 256))
    (location (string-ascii 64))
    (hourly-rate uint)
    (is-active bool)
)
    (let ((provider (unwrap! (map-get? service-providers tx-sender) ERR-NOT-FOUND)))
        ;; Check if contract is not paused
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        ;; Validate inputs
        (asserts! (is-valid-name-input name) ERR-INVALID-INPUT)
        (asserts! (is-valid-string-input description) ERR-INVALID-INPUT)
        (asserts! (is-valid-name-input location) ERR-INVALID-INPUT)
        ;; Validate hourly rate is greater than 0
        (asserts! (> hourly-rate u0) ERR-INVALID-PRICE)
        ;; Update provider information using safe string creation
        (map-set service-providers tx-sender (merge provider {
            name: (create-safe-name name),
            description: (create-safe-description description),
            location: (create-safe-location location),
            hourly-rate: hourly-rate,
            is-active: is-active
        }))
        (ok true)
    )
)

;; Function to purchase a 3D printing design
;; Transfers payment to creator and platform fee
(define-public (purchase-design (design-id uint))
    (let (
        (design (unwrap! (map-get? designs design-id) ERR-NOT-FOUND))
        (order-id (var-get next-order-id))
        (platform-fee (/ (* (get price design) (var-get platform-fee-bps)) u10000))
        (creator-payment (- (get price design) platform-fee))
    )
        ;; Check if contract is not paused
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        ;; Check if design is active
        (asserts! (get is-active design) ERR-INVALID-STATUS)
        ;; Prevent self-purchase
        (asserts! (not (is-eq tx-sender (get creator design))) ERR-SELF-PURCHASE)
        ;; Check if user hasn't already purchased this design
        (asserts! (not (has-purchased-design tx-sender design-id)) ERR-ALREADY-EXISTS)
        ;; Transfer payment to creator
        (try! (stx-transfer? creator-payment tx-sender (get creator design)))
        ;; Transfer platform fee to contract
        (try! (stx-transfer? platform-fee tx-sender (as-contract tx-sender)))
        ;; Record the purchase
        (map-set design-purchases {buyer: tx-sender, design-id: design-id} true)
        ;; Create order record
        (map-set orders order-id {
            buyer: tx-sender,
            seller: (get creator design),
            design-id: (some design-id),
            order-type: u1,
            total-amount: (get price design),
            status: STATUS-COMPLETED,
            created-at: block-height,
            completed-at: (some block-height),
            notes: "Design purchase"
        })
        ;; Update design sales count
        (map-set designs design-id (merge design {
            total-sales: (+ (get total-sales design) u1)
        }))
        ;; Update platform earnings
        (var-set total-platform-earnings (+ (var-get total-platform-earnings) platform-fee))
        ;; Increment order ID
        (var-set next-order-id (+ order-id u1))
        (ok order-id)
    )
)

;; Function to create a printing service order without design
;; Connects buyer with service provider for custom printing
(define-public (create-print-order-no-design
    (provider principal)
    (estimated-amount uint)
    (notes (string-ascii 256))
)
    (let (
        (provider-data (unwrap! (map-get? service-providers provider) ERR-NOT-FOUND))
        (order-id (var-get next-order-id))
    )
        ;; Check if contract is not paused
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        ;; Check if provider is active
        (asserts! (get is-active provider-data) ERR-INVALID-STATUS)
        ;; Prevent self-ordering
        (asserts! (not (is-eq tx-sender provider)) ERR-SELF-PURCHASE)
        ;; Validate inputs
        (asserts! (is-valid-string-input notes) ERR-INVALID-INPUT)
        ;; Validate estimated amount
        (asserts! (> estimated-amount u0) ERR-INVALID-PRICE)
        ;; Create order record using safe string creation
        (map-set orders order-id {
            buyer: tx-sender,
            seller: provider,
            design-id: none,
            order-type: u2,
            total-amount: estimated-amount,
            status: STATUS-PENDING,
            created-at: block-height,
            completed-at: none,
            notes: (create-safe-notes notes)
        })
        ;; Increment order ID
        (var-set next-order-id (+ order-id u1))
        (ok order-id)
    )
)

;; Function to create a printing service order with design
;; Connects buyer with service provider for printing a purchased design
(define-public (create-print-order-with-design
    (provider principal)
    (design-id uint)
    (estimated-amount uint)
    (notes (string-ascii 256))
)
    (let (
        (provider-data (unwrap! (map-get? service-providers provider) ERR-NOT-FOUND))
        (order-id (var-get next-order-id))
    )
        ;; Check if contract is not paused
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        ;; Check if provider is active
        (asserts! (get is-active provider-data) ERR-INVALID-STATUS)
        ;; Prevent self-ordering
        (asserts! (not (is-eq tx-sender provider)) ERR-SELF-PURCHASE)
        ;; Validate design ownership - this validates both existence and ownership
        (asserts! (validate-design-ownership tx-sender design-id) ERR-UNAUTHORIZED-ACCESS)
        ;; Validate inputs
        (asserts! (is-valid-string-input notes) ERR-INVALID-INPUT)
        ;; Validate estimated amount
        (asserts! (> estimated-amount u0) ERR-INVALID-PRICE)
        ;; Create order record using safe string creation
        (map-set orders order-id {
            buyer: tx-sender,
            seller: provider,
            design-id: (some design-id),
            order-type: u2,
            total-amount: estimated-amount,
            status: STATUS-PENDING,
            created-at: block-height,
            completed-at: none,
            notes: (create-safe-notes notes)
        })
        ;; Increment order ID
        (var-set next-order-id (+ order-id u1))
        (ok order-id)
    )
)

;; Function for service provider to update order status
;; Allows tracking of order progress through different stages
(define-public (update-order-status (order-id uint) (new-status uint))
    (let ((order (unwrap! (map-get? orders order-id) ERR-NOT-FOUND)))
        ;; Check if contract is not paused
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        ;; Check if caller is the seller (service provider)
        (asserts! (is-eq tx-sender (get seller order)) ERR-UNAUTHORIZED-ACCESS)
        ;; Validate status is within valid range
        (asserts! (and (>= new-status u1) (<= new-status u5)) ERR-INVALID-STATUS)
        ;; Update order status
        (map-set orders order-id (merge order {
            status: new-status,
            completed-at: (if (is-eq new-status STATUS-COMPLETED) 
                            (some block-height) 
                            (get completed-at order))
        }))
        ;; If order is completed, update provider stats
        (if (is-eq new-status STATUS-COMPLETED)
            (let ((provider (unwrap! (map-get? service-providers (get seller order)) ERR-NOT-FOUND)))
                (map-set service-providers (get seller order) (merge provider {
                    total-orders: (+ (get total-orders provider) u1)
                }))
            )
            true
        )
        (ok true)
    )
)

;; Function to complete a printing service order with payment
;; Buyer pays for completed printing service
(define-public (complete-print-order (order-id uint))
    (let (
        (order (unwrap! (map-get? orders order-id) ERR-NOT-FOUND))
        (platform-fee (/ (* (get total-amount order) (var-get platform-fee-bps)) u10000))
        (provider-payment (- (get total-amount order) platform-fee))
    )
        ;; Check if contract is not paused
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        ;; Check if caller is the buyer
        (asserts! (is-eq tx-sender (get buyer order)) ERR-UNAUTHORIZED-ACCESS)
        ;; Check if order is in progress
        (asserts! (is-eq (get status order) STATUS-IN-PROGRESS) ERR-INVALID-STATUS)
        ;; Transfer payment to service provider
        (try! (stx-transfer? provider-payment tx-sender (get seller order)))
        ;; Transfer platform fee to contract
        (try! (stx-transfer? platform-fee tx-sender (as-contract tx-sender)))
        ;; Update order status to completed
        (map-set orders order-id (merge order {
            status: STATUS-COMPLETED,
            completed-at: (some block-height)
        }))
        ;; Update platform earnings
        (var-set total-platform-earnings (+ (var-get total-platform-earnings) platform-fee))
        (ok true)
    )
)

;; Function to rate a purchased design
;; Allows buyers to rate designs they have purchased
(define-public (rate-design (design-id uint) (rating uint))
    (let ((design (unwrap! (map-get? designs design-id) ERR-NOT-FOUND)))
        ;; Check if contract is not paused
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        ;; Check if user has purchased the design
        (asserts! (has-purchased-design tx-sender design-id) ERR-UNAUTHORIZED-ACCESS)
        ;; Validate rating is between 1 and 5
        (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
        ;; Check if user hasn't already rated this design
        (asserts! (is-none (get-design-rating tx-sender design-id)) ERR-ALREADY-RATED)
        ;; Store the rating
        (map-set design-ratings {buyer: tx-sender, design-id: design-id} rating)
        ;; Update design rating statistics
        (let (
            (current-rating-count (get rating-count design))
            (current-avg-rating (get avg-rating design))
            (new-rating-count (+ current-rating-count u1))
            ;; Convert rating to 100-point scale for precision (5 stars = 500 points)
            (rating-points (* rating u100))
            ;; Calculate new average rating
            (new-avg-rating (/ (+ (* current-avg-rating current-rating-count) rating-points) new-rating-count))
        )
            (map-set designs design-id (merge design {
                avg-rating: new-avg-rating,
                rating-count: new-rating-count
            }))
        )
        (ok true)
    )
)

;; Function to rate a service provider
;; Allows buyers to rate service providers after completed orders
(define-public (rate-service-provider (provider principal) (order-id uint) (rating uint))
    (let (
        (order (unwrap! (map-get? orders order-id) ERR-NOT-FOUND))
        (provider-data (unwrap! (map-get? service-providers provider) ERR-NOT-FOUND))
    )
        ;; Check if contract is not paused
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        ;; Check if caller is the buyer from the order
        (asserts! (is-eq tx-sender (get buyer order)) ERR-UNAUTHORIZED-ACCESS)
        ;; Check if the order is with this provider and completed
        (asserts! (and (is-eq (get seller order) provider) 
                      (is-eq (get status order) STATUS-COMPLETED)) ERR-ORDER-NOT-COMPLETED)
        ;; Validate rating is between 1 and 5
        (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
        ;; Check if user hasn't already rated this provider
        (asserts! (is-none (get-provider-rating tx-sender provider)) ERR-ALREADY-RATED)
        ;; Store the rating
        (map-set provider-ratings {buyer: tx-sender, provider: provider} rating)
        ;; Update provider rating statistics
        (let (
            (current-rating-count (get rating-count provider-data))
            (current-avg-rating (get avg-rating provider-data))
            (new-rating-count (+ current-rating-count u1))
            ;; Convert rating to 100-point scale for precision
            (rating-points (* rating u100))
            ;; Calculate new average rating
            (new-avg-rating (/ (+ (* current-avg-rating current-rating-count) rating-points) new-rating-count))
        )
            (map-set service-providers provider (merge provider-data {
                avg-rating: new-avg-rating,
                rating-count: new-rating-count
            }))
        )
        (ok true)
    )
)

;; Admin function to withdraw platform earnings
;; Only contract owner can withdraw accumulated fees
(define-public (withdraw-platform-earnings (amount uint))
    (let ((current-balance (stx-get-balance (as-contract tx-sender))))
        ;; Check if caller is contract owner
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED-ACCESS)
        ;; Check if contract has sufficient balance
        (asserts! (<= amount current-balance) ERR-INSUFFICIENT-FUNDS)
        ;; Transfer earnings to owner
        (try! (as-contract (stx-transfer? amount tx-sender CONTRACT-OWNER)))
        (ok true)
    )
)