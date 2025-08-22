;; Mission Planner Contract
;; Manages regulatory approvals, safety protocols, and technical requirements

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-INPUT (err u301))
(define-constant ERR-MISSION-NOT-FOUND (err u302))
(define-constant ERR-APPROVAL-PENDING (err u303))
(define-constant ERR-SAFETY-VIOLATION (err u304))

;; Data Variables
(define-data-var next-mission-id uint u1)
(define-data-var next-approval-id uint u1)

;; Data Maps
(define-map missions
  { mission-id: uint }
  {
    launch-id: uint,
    mission-name: (string-ascii 100),
    operator: principal,
    mission-type: (string-ascii 50),
    risk-level: uint,
    status: (string-ascii 20),
    created-at: uint,
    launch-date: uint,
    abort-criteria: (string-ascii 200)
  }
)

(define-map regulatory-approvals
  { approval-id: uint }
  {
    mission-id: uint,
    authority: (string-ascii 50),
    approval-type: (string-ascii 50),
    status: (string-ascii 20),
    submitted-at: uint,
    approved-at: (optional uint),
    expires-at: (optional uint),
    conditions: (string-ascii 300)
  }
)

(define-map safety-protocols
  { mission-id: uint, protocol-type: (string-ascii 50) }
  {
    description: (string-ascii 200),
    mandatory: bool,
    completed: bool,
    verified-by: (optional principal),
    verified-at: (optional uint)
  }
)

(define-map technical-requirements
  { mission-id: uint, requirement-id: uint }
  {
    description: (string-ascii 200),
    category: (string-ascii 50),
    status: (string-ascii 20),
    assigned-to: (optional principal),
    due-date: uint,
    completed-at: (optional uint)
  }
)

;; Public Functions

;; Create a new mission plan
(define-public (create-mission
  (launch-id uint)
  (mission-name (string-ascii 100))
  (mission-type (string-ascii 50))
  (risk-level uint)
  (launch-date uint)
  (abort-criteria (string-ascii 200))
)
  (let ((mission-id (var-get next-mission-id)))
    ;; replaced &lt;= with <= for native Clarity syntax
    (asserts! (<= risk-level u10) ERR-INVALID-INPUT)
    (asserts! (> launch-date block-height) ERR-INVALID-INPUT)

    (map-set missions
      { mission-id: mission-id }
      {
        launch-id: launch-id,
        mission-name: mission-name,
        operator: tx-sender,
        mission-type: mission-type,
        risk-level: risk-level,
        status: "planning",
        created-at: block-height,
        launch-date: launch-date,
        abort-criteria: abort-criteria
      }
    )

    (var-set next-mission-id (+ mission-id u1))
    (print { event: "mission-created", mission-id: mission-id, operator: tx-sender })
    (ok mission-id)
  )
)

;; Submit regulatory approval request
(define-public (submit-approval-request
  (mission-id uint)
  (authority (string-ascii 50))
  (approval-type (string-ascii 50))
  (conditions (string-ascii 300))
)
  (let ((approval-id (var-get next-approval-id))
        (mission (unwrap! (map-get? missions { mission-id: mission-id }) ERR-MISSION-NOT-FOUND)))

    (asserts! (is-eq (get operator mission) tx-sender) ERR-NOT-AUTHORIZED)

    (map-set regulatory-approvals
      { approval-id: approval-id }
      {
        mission-id: mission-id,
        authority: authority,
        approval-type: approval-type,
        status: "submitted",
        submitted-at: block-height,
        approved-at: none,
        expires-at: none,
        conditions: conditions
      }
    )

    (var-set next-approval-id (+ approval-id u1))
    (print { event: "approval-submitted", approval-id: approval-id, mission-id: mission-id })
    (ok approval-id)
  )
)

;; Update approval status (for regulatory authorities)
(define-public (update-approval-status (approval-id uint) (new-status (string-ascii 20)) (expires-at (optional uint)))
  (let ((approval (unwrap! (map-get? regulatory-approvals { approval-id: approval-id }) ERR-INVALID-INPUT)))
    ;; In a real system, this would check if tx-sender is an authorized regulatory authority

    (map-set regulatory-approvals
      { approval-id: approval-id }
      (merge approval {
        status: new-status,
        approved-at: (if (is-eq new-status "approved") (some block-height) none),
        expires-at: expires-at
      })
    )

    (print { event: "approval-updated", approval-id: approval-id, status: new-status })
    (ok true)
  )
)

;; Add safety protocol
(define-public (add-safety-protocol
  (mission-id uint)
  (protocol-type (string-ascii 50))
  (description (string-ascii 200))
  (mandatory bool)
)
  (let ((mission (unwrap! (map-get? missions { mission-id: mission-id }) ERR-MISSION-NOT-FOUND)))
    (asserts! (is-eq (get operator mission) tx-sender) ERR-NOT-AUTHORIZED)

    (map-set safety-protocols
      { mission-id: mission-id, protocol-type: protocol-type }
      {
        description: description,
        mandatory: mandatory,
        completed: false,
        verified-by: none,
        verified-at: none
      }
    )

    (print { event: "safety-protocol-added", mission-id: mission-id, protocol-type: protocol-type })
    (ok true)
  )
)

;; Complete safety protocol
(define-public (complete-safety-protocol (mission-id uint) (protocol-type (string-ascii 50)))
  (let ((protocol (unwrap! (map-get? safety-protocols { mission-id: mission-id, protocol-type: protocol-type }) ERR-INVALID-INPUT))
        (mission (unwrap! (map-get? missions { mission-id: mission-id }) ERR-MISSION-NOT-FOUND)))

    (asserts! (is-eq (get operator mission) tx-sender) ERR-NOT-AUTHORIZED)

    (map-set safety-protocols
      { mission-id: mission-id, protocol-type: protocol-type }
      (merge protocol {
        completed: true,
        verified-by: (some tx-sender),
        verified-at: (some block-height)
      })
    )

    (print { event: "safety-protocol-completed", mission-id: mission-id, protocol-type: protocol-type })
    (ok true)
  )
)

;; Update mission status
(define-public (update-mission-status (mission-id uint) (new-status (string-ascii 20)))
  (let ((mission (unwrap! (map-get? missions { mission-id: mission-id }) ERR-MISSION-NOT-FOUND)))
    (asserts! (is-eq (get operator mission) tx-sender) ERR-NOT-AUTHORIZED)

    ;; Check if all mandatory safety protocols are completed before allowing "approved" status
    (asserts! (or (not (is-eq new-status "approved")) (check-mandatory-protocols-complete mission-id)) ERR-SAFETY-VIOLATION)

    (map-set missions
      { mission-id: mission-id }
      (merge mission { status: new-status })
    )

    (print { event: "mission-status-updated", mission-id: mission-id, status: new-status })
    (ok true)
  )
)

;; Read-only Functions

;; Get mission details
(define-read-only (get-mission (mission-id uint))
  (map-get? missions { mission-id: mission-id })
)

;; Get approval details
(define-read-only (get-approval (approval-id uint))
  (map-get? regulatory-approvals { approval-id: approval-id })
)

;; Get safety protocol status
(define-read-only (get-safety-protocol (mission-id uint) (protocol-type (string-ascii 50)))
  (map-get? safety-protocols { mission-id: mission-id, protocol-type: protocol-type })
)

;; Check if mission is ready for launch
(define-read-only (is-mission-ready (mission-id uint))
  ;; Fixed type mismatch by using match instead of unwrap! with err
  (match (map-get? missions { mission-id: mission-id })
    mission (and
      (is-eq (get status mission) "approved")
      (check-mandatory-protocols-complete mission-id)
      (check-approvals-valid mission-id)
    )
    false ;; Return false if mission not found
  )
)

;; Get next mission ID
(define-read-only (get-next-mission-id)
  (var-get next-mission-id)
)

;; Get next approval ID
(define-read-only (get-next-approval-id)
  (var-get next-approval-id)
)

;; Private Functions

;; Check if all mandatory safety protocols are completed
(define-private (check-mandatory-protocols-complete (mission-id uint))
  ;; Simplified check - in a real system this would iterate through all protocols
  true
)

;; Check if all required approvals are valid and not expired
(define-private (check-approvals-valid (mission-id uint))
  ;; Simplified check - in a real system this would check all approvals for the mission
  true
)
