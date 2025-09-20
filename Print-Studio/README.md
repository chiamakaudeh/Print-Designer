# 3D Printing Marketplace Smart Contract

A decentralized marketplace built on Stacks blockchain for trading 3D printing designs and connecting users with printing service providers.

## Overview

This smart contract enables a peer-to-peer marketplace where designers can sell their 3D printing designs and service providers can offer printing services. The platform handles payments, ratings, and order management through blockchain technology.

## Features

### Core Functionality
- **Design Marketplace**: Upload and sell 3D printing designs
- **Service Provider Network**: Connect with local 3D printing services
- **Secure Payments**: Automated payment processing with platform fees
- **Rating System**: Rate designs and service providers
- **Order Management**: Track orders from creation to completion
- **Administrative Controls**: Contract pause functionality and fee management

### Design Categories
1. Electronics
2. Automotive
3. Home & Garden
4. Toys & Games
5. Jewelry & Accessories
6. Other

### Order Statuses
1. Pending
2. In Progress
3. Completed
4. Cancelled
5. Disputed

## Contract Structure

### Data Maps
- `designs`: Stores design information and metadata
- `service-providers`: Service provider profiles and ratings
- `orders`: Order tracking and history
- `design-purchases`: Tracks design ownership
- `design-ratings`: User ratings for designs
- `provider-ratings`: User ratings for service providers

### Key Variables
- `platform-fee-bps`: Platform fee in basis points (default: 250 = 2.5%)
- `contract-paused`: Emergency pause state
- `next-design-id`: Auto-incrementing design ID counter
- `next-order-id`: Auto-incrementing order ID counter

## Functions

### Read-Only Functions

#### `is-contract-paused`
Returns the current pause state of the contract.

#### `get-platform-fee`
Returns the current platform fee in basis points.

#### `get-design (design-id)`
Retrieves design information by ID.

#### `get-service-provider (provider)`
Retrieves service provider information by principal address.

#### `get-order (order-id)`
Retrieves order information by ID.

#### `has-purchased-design (buyer, design-id)`
Checks if a user has purchased a specific design.

#### `get-design-rating (buyer, design-id)`
Gets a user's rating for a specific design.

#### `get-provider-rating (buyer, provider)`
Gets a user's rating for a specific service provider.

#### `get-platform-earnings`
Returns total platform earnings accumulated.

### Public Functions

#### Administrative Functions

##### `set-contract-pause (paused)`
**Permissions**: Contract owner only
Pauses or unpauses the contract for emergency situations.

##### `set-platform-fee (fee-bps)`
**Permissions**: Contract owner only
Updates the platform fee (maximum 10% = 1000 basis points).

##### `withdraw-platform-earnings (amount)`
**Permissions**: Contract owner only
Withdraws accumulated platform fees.

#### Design Management

##### `create-design (name, description, category, price, file-hash, preview-hash)`
Creates a new 3D printing design listing.

**Parameters**:
- `name`: Design name (max 64 characters)
- `description`: Design description (max 256 characters)
- `category`: Category ID (1-6)
- `price`: Price in microSTX
- `file-hash`: IPFS hash of design file
- `preview-hash`: IPFS hash of preview image

##### `update-design (design-id, name, description, price, is-active)`
**Permissions**: Design creator only
Updates an existing design listing.

##### `purchase-design (design-id)`
Purchases a design and transfers ownership to buyer.

##### `rate-design (design-id, rating)`
**Requirements**: Must own the design
Rates a purchased design (1-5 stars).

#### Service Provider Management

##### `register-service-provider (name, description, location, hourly-rate)`
Registers as a 3D printing service provider.

**Parameters**:
- `name`: Business name (max 64 characters)
- `description`: Service description (max 256 characters)
- `location`: Geographic location (max 64 characters)
- `hourly-rate`: Rate in microSTX per hour

##### `update-service-provider (name, description, location, hourly-rate, is-active)`
**Permissions**: Service provider only
Updates service provider profile.

#### Order Management

##### `create-print-order (provider, design-id, estimated-amount, notes)`
Creates a printing service order.

**Parameters**:
- `provider`: Service provider's principal address
- `design-id`: Optional design ID if using owned design
- `estimated-amount`: Estimated cost in microSTX
- `notes`: Additional order notes (max 256 characters)

##### `update-order-status (order-id, new-status)`
**Permissions**: Service provider only
Updates the status of a printing order.

##### `complete-print-order (order-id)`
**Permissions**: Order buyer only
Completes payment for a printing service order.

##### `rate-service-provider (provider, order-id, rating)`
**Requirements**: Must have completed order with provider
Rates a service provider (1-5 stars).

## Usage Examples

### Creating a Design
```clarity
(contract-call? .marketplace create-design
    "Smartphone Stand"
    "Adjustable phone stand for desk use"
    u3  ; Home category
    u5000000  ; 5 STX price
    "QmX1Y2Z3..."  ; IPFS file hash
    "QmA4B5C6..."  ; IPFS preview hash
)
```

### Purchasing a Design
```clarity
(contract-call? .marketplace purchase-design u1)
```

### Registering as Service Provider
```clarity
(contract-call? .marketplace register-service-provider
    "3D Print Pro"
    "Professional 3D printing services with fast turnaround"
    "New York, NY"
    u1000000  ; 1 STX per hour
)
```

### Creating a Print Order
```clarity
(contract-call? .marketplace create-print-order
    'SP1ABC...  ; Provider address
    (some u1)   ; Design ID
    u10000000   ; 10 STX estimated cost
    "Please print in PLA plastic, blue color"
)
```

## Error Codes

- `u404`: Not found
- `u401`: Unauthorized access
- `u400`: Invalid price
- `u402`: Insufficient funds
- `u409`: Already exists
- `u422`: Invalid status
- `u403`: Self-purchase attempt
- `u405`: Invalid rating
- `u406`: Order not completed
- `u407`: Already rated
- `u503`: Contract paused

## Platform Economics

### Fee Structure
- Default platform fee: 2.5% of transaction value
- Fees are automatically deducted from payments
- Creators and service providers receive the remainder

### Payment Flow
1. **Design Purchase**: Buyer → Creator (97.5%) + Platform (2.5%)
2. **Print Service**: Buyer → Provider (97.5%) + Platform (2.5%)

## Security Features

- **Access Control**: Function-level permissions
- **Emergency Pause**: Admin can halt all operations
- **Self-Purchase Prevention**: Users cannot buy from themselves
- **Double-Purchase Protection**: Cannot buy same design twice
- **Rating Limits**: One rating per user per item/service

## Deployment Requirements

- Stacks blockchain network
- Clarity smart contract runtime
- IPFS or similar storage for design files and previews

## Development

### Prerequisites
- Clarinet CLI for local development
- Stacks wallet for testnet/mainnet deployment

### Testing
```bash
clarinet test
```

### Deployment
```bash
clarinet deploy --testnet
```