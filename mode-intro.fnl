(local camera (require "lib.camera"))
(local timer (require "lib.timer"))
(local attack-timer (require "lib.timer"))
(local json-decoder (require "lib.dkjson"))

(var cam (camera))

(local filemap {:level-001 "assets/level-info/level-1.json"
                :level-002 "assets/level-info/level-2.json"})

(var general-state {:file-to-load :level-001})

;; Load JSON data
(fn load-file-data [path]
  (let [raw-data (love.filesystem.read path)
        data-table (json-decoder.decode raw-data)]
    data-table))

(fn load-world-data []
  (let [file-to-load (. general-state :file-to-load)
        file-path (. filemap file-to-load)]
    (load-file-data file-path)))

(var world-data (load-world-data))

(fn process-initial-lisper-position [world-data]
  {:x (. world-data "initial_player_position" "x")
   :y (. world-data "initial_player_position" "y")})

(process-initial-lisper-position world-data)


(fn calculate-screen-center []
  (local (w h _flags) (love.window.getMode))
  {:x (- (/ w 2) 8) :y (- (/ h 2) 8)})

(var lisper-state {:animation-to-load "idle"
                   :is-moving false
                   :is-accelerating false
                   :position (process-initial-lisper-position world-data)
                   :velocity {:x 0 :y 0}
                   :acceleration {:x 0 :y -0.001}
                   :friction {:x 0 :y -0.0001}
                   :lisp-shield-energy 500
                   :hp 500
                   :angle 0
                   :is-shooting false
                   :target-shoot {:x 0 :y 0}
                   :mines []
                   :range 150})

(var enemy-one-state {:animation-to-load "moving"
                      :is-moving false
                      :position {:x 100 :y 100}
                      :velocity {:x 0 :y 0.4}
                      :hp 90})

(local enemy-template {:animation-to-load "moving"
                       :is-moving false
                       :position {:x 100 :y 100}
                       :velocity {:x 0 :y 0.4}
                       :hp 90})

(var enemy-swarm [])

(var objectives [])

(fn load-image [path]
  (let [image (love.graphics.newImage path)]
    (image:setFilter "nearest")
    image))

(fn create-animation [image  width height duration initial-frame ending-frame]
  (local animation {})
  (tset animation :sprite-batch image)
  (tset animation :quads {})
  (for [y 0 (- (image:getHeight) height) height]
    (for [x (* initial-frame width) (- (image:getWidth) (- (image:getWidth) (* ending-frame width))) width]
      (let [quads (. animation :quads)]
        (table.insert (. animation :quads) (love.graphics.newQuad x y width height (image:getDimensions))))))
  (tset animation :duration (or duration 1))
  (tset animation :current-time 0)
  animation)

(fn calculate-actual-frame [animation]
  (+ 1 (math.floor (* (/ (. animation :current-time) (. animation :duration)) (# (. animation :quads))))))

(fn coordinate-animation [animation delta]
  (tset animation :current-time (+ (. animation :current-time) delta))
  (when (>= (. animation :current-time) (. animation :duration))
    (tset animation :current-time (- (. animation :current-time) (. animation :duration)))))

                                        ; (love.graphics.setNewFont 30)
;; Loading Images
(local lisper-image (load-image "assets/lisp_battle.png"))
(local background (load-image "assets/Background.png"))
(local enemy-one-image (load-image "assets/enemies.png"))
(local objective-image (load-image "assets/mineral_demo.png"))
(local enemy-nest-image (load-image "assets/nest.png"))
(local bullet-image (load-image "assets/bfg_ball.png"))

(fn load-mines []
  (for [i 1 60]
    (let [image (load-image "assets/bfg_ball.png")]
      (table.insert (. lisper-state :mines) {:consumed false :image image :x 0 :y 0}))))

(load-mines)

(var world-mines [])

(fn consume-mine []
  (when (> (# (. lisper-state :mines)) 0)
    (let [mine (table.remove (. lisper-state :mines))]
      (tset mine :x (. lisper-state :target-shoot :x))
      (tset mine :y (. lisper-state :target-shoot :y))
      (table.insert world-mines mine))))

;; Loading animations
(local lisper-idle-animation (create-animation lisper-image 16 16 0.2 0 1))
(local lisper-vertical-animation (create-animation lisper-image 16 16 0.4 2 5))
(local lisper-turn-right-animation (create-animation lisper-image 16 16 0.4 10 13))
(local lisper-turn-left-animation (create-animation lisper-image 16 16 0.4 6 9))
(local enemy-one-idle-animation (create-animation enemy-one-image 16 16 0.4 0 3))
(local enemy-one-moving-animation (create-animation enemy-one-image 16 16 0.4 4 7))
(local mineral-shine-animation (create-animation objective-image 16 16 0.8 0 8))
(local enemy-nest-idle-animation (create-animation enemy-nest-image 16 16 0.3 0 2))

;; Init frames
(var lisper-idle-frame (calculate-actual-frame lisper-idle-animation))
(var lisper-vertical-frame  (calculate-actual-frame lisper-vertical-animation))
(var lisper-turn-right-frame (calculate-actual-frame lisper-turn-right-animation))
(var lisper-turn-left-frame (calculate-actual-frame lisper-turn-left-animation))
(var enemy-one-idle-frame (calculate-actual-frame enemy-one-idle-animation))
(var enemy-one-moving-frame (calculate-actual-frame enemy-one-moving-animation))
(var mineral-shine-frame (calculate-actual-frame mineral-shine-animation))
(var enemy-nest-idle-frame (calculate-actual-frame  enemy-nest-idle-animation))

(var lisper-animation-map {"idle" {:animation lisper-idle-animation :frame lisper-idle-frame}
                           "accelerate" {:animation lisper-vertical-animation :frame lisper-vertical-frame}
                           "turn-right" {:animation lisper-turn-right-animation :frame lisper-turn-right-frame}
                           "turn-left" {:animation lisper-turn-left-animation :frame lisper-turn-left-frame}})

(var enemy-one-animation-map {"idle" {:animation enemy-one-idle-animation :frame enemy-one-idle-frame}
                              "moving" {:animation enemy-one-moving-animation :frame enemy-one-moving-frame}})

(var enemy-nest-animation-map {"idle" {:animation enemy-nest-idle-animation :frame enemy-nest-idle-frame}})

(var mineral-shine-animation-map {"shine" {:animation mineral-shine-animation :frame mineral-shine-frame}})

;; Run animations by state
(fn animate-by-state [state animation-map state-table scale-x scale-y]
  (let [animation (. animation-map state :animation)
        frame (. animation-map state :frame)]
    (love.graphics.draw (. animation :sprite-batch) ;; Image
                        (. (. animation :quads) frame) ;; Quads
                        (. state-table :position :x) ;; Coord x
                        (. state-table :position :y) ;; Coord y
                        (. state-table :angle) ;; Rotation Angle
                        scale-x ;; Scale x
                        scale-y ;; Scale y
                        8 
                        8)))

;; Movement
(fn verify-moving []
  (let [vx (. lisper-state :velocity :x)
        vy (. lisper-state :velocity :y)]
    (not (and (= vx 0) (= vy 0)))))

(fn accelerate-lisper []
  (let [actual-vx (. lisper-state :velocity :x)
        actual-vy (. lisper-state :velocity :y)
        new-vx (+ actual-vx (. lisper-state :acceleration :x))
        new-vy (+ actual-vy (. lisper-state :acceleration :y))]
    (when (< (math.abs actual-vy) 0.8)
      (tset lisper-state :velocity :x new-vx)
      (tset lisper-state :velocity :y new-vy))))

(fn change-velocity []
  (let [actual-vx (. lisper-state :velocity :x)
        actual-vy (. lisper-state :velocity :y)
        new-vx (- actual-vx (. lisper-state :friction :x))
        new-vy (- actual-vy (. lisper-state :friction :y))]
    (if (. lisper-state :is-moving)
        (do
          (if (< (math.abs new-vy) 1.04)
              (do
                (tset lisper-state :velocity :x new-vx)
                (tset lisper-state :velocity :y new-vy))
              (do
                (tset lisper-state :velocity :x actual-vx)
                (tset lisper-state :velocity :y actual-vy))))
        (do
          (tset lisper-state :velocity :x 0)
          (tset lisper-state :velocity :y 0)))))

;; Limits
;; Inferior Izquierda (46, 2354)
;; Superior Derecha (3790, 60)
(fn is-lisper-inside-limits [lisper-x-position lisper-y-position]
  (and (< lisper-x-position 3790)
       (< lisper-y-position 2354)
       (> lisper-x-position 46)
       (> lisper-y-position 60)))

(fn move-lisper []
  (let [actual-position-x (. lisper-state :position :x)
        actual-position-y (. lisper-state :position :y)
        angle (. lisper-state :angle)
        new-position-x (+ actual-position-x (* (math.cos (+ angle (/ math.pi 2))) (. lisper-state :velocity :y)))
        new-position-y (+ actual-position-y (* (math.sin (+ angle (/ math.pi 2))) (. lisper-state :velocity :y)))]
    (when (is-lisper-inside-limits new-position-x new-position-y)
      (tset lisper-state :position :x new-position-x)
      (tset lisper-state :position :y new-position-y))))

(fn move-enemy [dt speed]
  (let [actual-enemy-position-x (. enemy-one-state :position :x)
        actual-enemy-position-y (. enemy-one-state :position :y)
        actual-lisper-position-x (. lisper-state :position :x)
        actual-lisper-position-y (. lisper-state :position :y)
        dist-x (- actual-lisper-position-x actual-enemy-position-x)
        dist-y (- actual-lisper-position-y actual-enemy-position-y)
        direction (math.atan2 dist-y dist-x)
        new-enemy-position-x (+ actual-enemy-position-x (* (* speed (math.cos direction)) dt))
        new-enemy-position-y (+ actual-enemy-position-y (* (* speed (math.sin direction)) dt))]
    (tset enemy-one-state :position :x new-enemy-position-x)
    (tset enemy-one-state :position :y new-enemy-position-y)))

(fn move-enemies [dt speed]
  (for [i 1 (# enemy-swarm)]
    (let [enemy (. enemy-swarm i)
          actual-enemy-position-x (. enemy :position :x)
          actual-enemy-position-y (. enemy :position :y)
          actual-lisper-position-x (. lisper-state :position :x)
          actual-lisper-position-y (. lisper-state :position :y)
          dist-x (- actual-lisper-position-x actual-enemy-position-x)
          dist-y (- actual-lisper-position-y actual-enemy-position-y)
          direction (math.atan2 dist-y dist-x)
          new-enemy-position-x (+ actual-enemy-position-x (* (* speed (math.cos direction)) dt))
          new-enemy-position-y (+ actual-enemy-position-y (* (* speed (math.sin direction)) dt))]
      (tset enemy :position :x new-enemy-position-x)
      (tset enemy :position :y new-enemy-position-y))))

;; Collisions TODO Enemies, bullet
(fn check-lisper-collision [enemy r]
  (let [enemy-x (. enemy :position :x)
        enemy-y (. enemy :position :y)
        lisper-x (+ (. lisper-state :position :x) 0)
        lisper-y (+ (. lisper-state :position :y) 0)
        diff-x (- lisper-x enemy-x)
        diff-y (- lisper-y enemy-y)]
    (<= (math.sqrt (+ (* diff-x diff-x) (* diff-y diff-y))) r)))

(fn execute-enemy-attacks []
  (for [i 1 (# enemy-swarm)]
    (let [enemy (. enemy-swarm i)]
      (when (check-lisper-collision enemy 15)
        (tset lisper-state :hp (- (. lisper-state :hp) 40))))))

;; Enemies TODO
(fn create-new-enemy []
  (let [new-enemy {}]
    (each [key value (pairs enemy-template)]
      (tset new-enemy key value)
      (when (= key :position)
        (tset new-enemy :position :x (love.math.random 0 1000))
        (tset new-enemy :position :y (love.math.random 0 1000))))
    (table.insert enemy-swarm new-enemy)))

(fn feed-swarm [target-swarm]
  (for [i 1 (. target-swarm "enemy_number")]
    (let [radio (. target-swarm "radio")
          swarm-pos-x (. target-swarm "position" "x")
          swarm-pos-y (. target-swarm "position" "y")
          enemy-pos-x (+ swarm-pos-x (love.math.random (- 0 radio) radio))
          enemy-pos-y (+ swarm-pos-y (love.math.random (- 0 radio) radio))
          enemy-template (. target-swarm "enemy_template")
          new-enemy {:animation-to-load "moving"
                     :is-moving false
                     :position {:x enemy-pos-x :y enemy-pos-y}
                     :hp (. enemy-template "hp")}]
      (table.insert (. target-swarm "units") new-enemy))))

(fn feed-all-swarms [world-data]
  (let [swarms (. world-data "swarms")]
    (for [i 1 (# swarms)]
      (feed-swarm (. swarms i)))))

(feed-all-swarms world-data)

(fn spawn-enemy [target-swarm]
  (when (> (# (. target-swarm "units")) 0)
    (table.insert enemy-swarm (table.remove (. target-swarm "units")))))

(fn spawn-all-enemies []
  (let [swarms (. world-data "swarms")]
    (each [k v (pairs swarms)]
      (spawn-enemy v))))

(timer.every 4 (hashfn (spawn-all-enemies)))

(fn verify-dead [enemy]
  (<= (. enemy :hp) 0))

(attack-timer.every 0.7 (hashfn (execute-enemy-attacks)))

(var mine-consumed false)

(fn execute-mines-explosions []
  (for [i 1 (# world-mines)]
    (set mine-consumed false)
    (for [j 1 (# enemy-swarm)]
      (let [mine (. world-mines i)
            mine-x (. mine :x)
            mine-y (. mine :y)
            enemy (. enemy-swarm j)
            enemy-x (. enemy :position :x)
            enemy-y (. enemy :position :y)
            dist-x (- enemy-x mine-x)
            dist-y (- enemy-y mine-y)
            distance (math.sqrt (+ (* dist-x dist-x) (* dist-y dist-y)))]
        (when (and (<= distance 50) (not (. mine :consumed)) (not (verify-dead enemy)))
          (tset enemy-swarm j :hp (- (. enemy :hp) 500))
          (set mine-consumed true))))
    (when mine-consumed
      (tset world-mines i :consumed mine-consumed))))

;; objectives

(fn world-data-item-to-objective [location]
  (let [result {:position {:x (. location "x")
                           :y (. location "y")}}]
    result))

(fn verify-objectives-discovered []
  (let [lisper-x (. lisper-state :position :x)
        lisper-y (. lisper-state :position :y)
        objectives (. world-data "objectives" 1 "locations")]
    (for [i 1 (# objectives)]
      (let [objective (. objectives i)
            obj-x (. objective "x")
            obj-y (. objective "y")
            dist-x (- obj-x lisper-x)
            dist-y (- obj-y lisper-y)
            distance (math.sqrt (+ (* dist-x dist-x) (* dist-y dist-y)))]
        (when (and (not (. objective "discovered"))
                   (< distance 10))
          (tset world-data "objectives" 1 "locations" i "discovered" true)
          (print "Discovered"))))))

(fn count-discovered-objectives []
  (var discovered 0)
  (let [objectives (. world-data "objectives" 1 "locations")]
    (for [i 1 (# objectives)]
      (let [objective (. objectives i)]
        (when (. objective "discovered")
          (set discovered (+ 1 discovered)))))))

;; Lisper shoot tranforms
(fn lisper-shoot-transform [x1 y1 range]
  (let [angle (. lisper-state :angle)
        x2 (- x1 (* (math.cos (+ angle (/ math.pi 2))) (/ range 2)))
        y2 (- y1 (* (math.sin (+ angle (/ math.pi 2))) (/ range 2)))]
    {:x x2 :y y2}))


{:draw (fn draw [message]
         (cam:attach)
         (local center-coords (calculate-screen-center))


         (love.graphics.draw background 0 0 0 3 3)
         (when (. lisper-state :is-shooting)
           (let [mine (. world-mines (# world-mines))
                 mine-image (. mine :image)
                 x (. mine :x)
                 y (. mine :y)]
             (love.graphics.draw mine-image x y 0 1 1)
             (tset lisper-state :is-shooting false)))

         (for [i 1 (# world-mines)]
           (when (not (. world-mines i :consumed))
             (love.graphics.draw (. world-mines i :image) (. world-mines i :x) (. world-mines i :y))))
         
         (for [i 1 (# (. world-data "swarms"))]
           (animate-by-state "idle" enemy-nest-animation-map (. world-data "swarms" i) 4 4))

         (for [i 1 (# (. world-data "objectives" 1 "locations"))]
           (animate-by-state "shine" mineral-shine-animation-map (world-data-item-to-objective (. (. world-data "objectives" 1 "locations") i)) 3 3)) ;; This can be done better

         (for [i 1 (# enemy-swarm)]
           (when (not (verify-dead (. enemy-swarm i)))
             (animate-by-state "moving" enemy-one-animation-map (. enemy-swarm i) 3 3)))
         (animate-by-state (. lisper-state :animation-to-load) lisper-animation-map lisper-state 6 6)
         (cam:detach))

 :update (fn update [dt set-mode]
           (coordinate-animation lisper-idle-animation dt)
           (coordinate-animation lisper-vertical-animation dt)
           (coordinate-animation lisper-turn-right-animation dt)
           (coordinate-animation lisper-turn-left-animation dt)
           (coordinate-animation enemy-one-idle-animation dt)
           (coordinate-animation enemy-one-moving-animation dt)
           (coordinate-animation mineral-shine-animation dt)
           (coordinate-animation enemy-nest-idle-animation dt)

           ;; Setting lisper stuff
           (set lisper-idle-frame (calculate-actual-frame lisper-idle-animation))
           (tset lisper-animation-map "idle" :frame lisper-idle-frame)

           (set lisper-vertical-frame  (calculate-actual-frame lisper-vertical-animation))
           (tset lisper-animation-map "accelerate" :frame lisper-vertical-frame)

           (set lisper-turn-right-frame (calculate-actual-frame lisper-turn-right-animation))
           (tset lisper-animation-map "turn-right" :frame lisper-turn-right-frame)

           (set lisper-turn-left-frame (calculate-actual-frame lisper-turn-left-animation))
           (tset lisper-animation-map "turn-left" :frame lisper-turn-left-frame)

           ;; Setting enemy stuff
           (set enemy-one-idle-frame (calculate-actual-frame enemy-one-idle-animation))
           (tset enemy-one-animation-map "idle" :frame enemy-one-idle-frame)

           (set enemy-one-moving-frame  (calculate-actual-frame enemy-one-moving-animation))
           (tset enemy-one-animation-map "moving" :frame enemy-one-moving-frame)

           ;; Setting objectives
           (set mineral-shine-frame (calculate-actual-frame mineral-shine-animation))
           (tset mineral-shine-animation-map "shine" :frame mineral-shine-frame)

           ;; Setting enemy nests
           (set enemy-nest-idle-frame (calculate-actual-frame enemy-nest-idle-animation))
           (tset enemy-nest-animation-map "idle" :frame enemy-nest-idle-frame)

           ;; (if (check-lisper-collision enemy-one-state 4)
           ;;     (print "Here"))
           (when (love.keyboard.isDown "space")
             (tset lisper-state :animation-to-load "accelerate")
             (accelerate-lisper)
             (tset lisper-state :is-accelerating true)
             (tset lisper-state :is-moving true))
           (when (love.keyboard.isDown "right")
             (tset lisper-state :animation-to-load "turn-right")
             (tset lisper-state :angle (+ (. lisper-state :angle) 0.006)))
           (when (love.keyboard.isDown "left")
             (tset lisper-state :animation-to-load "turn-left")
             (tset lisper-state :angle (- (. lisper-state :angle) 0.006)))
           (when (and (not (or (love.keyboard.isDown "space") (love.keyboard.isDown "right") (love.keyboard.isDown "left")))
                      (not (. lisper-state :is-moving)))
             (tset lisper-state :animation-to-load "idle")
             (tset lisper-state :is-moving false))
           (change-velocity)
           (move-enemies dt 120)
           (move-lisper)
           (execute-mines-explosions)
           (cam:lookAt (. lisper-state :position :x) (. lisper-state :position :y))
           (timer.update dt))
 :keypressed (fn keypressed [key set-mode]
               key)
 :love.keyreleased (fn love.keyreleased [key]
                     (when (= key "space")
                       (tset lisper-state :is-moving false))
                     (when (= key "return")
                       (tset lisper-state :is-shooting true)
                       (let [x1 (. lisper-state :position :x)
                             y1 (. lisper-state :position :y)
                             range (. lisper-state :range)
                             transform (lisper-shoot-transform x1 y1 range)
                             x2 (. transform :x)
                             y2 (. transform :y)
                             dist-x (- x2 x1)
                             dist-y (- y2 y1)]
                         (tset lisper-state :target-shoot (lisper-shoot-transform x1 y1 range))
                         (consume-mine)))
                     (when (= key "down")
                       (print (count-discovered-objectives))
                       (verify-objectives-discovered)))}


;; (love.graphics.printf
;;  (: "Love Version: %s.%s.%s"
;;     :format  major minor revision) 0 10 w :center)
;; (love.graphics.printf
;;  (: "This window should close in %0.1f seconds"
;;     :format (math.max 0 (- 12 time)))
;;  0 (- (/ h 2) 15) w :center)




