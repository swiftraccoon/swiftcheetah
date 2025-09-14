import Foundation

/// User-configurable parameters for cycling simulation
public struct CyclingConfiguration {
    /// Rider and equipment parameters
    public struct RiderParameters {
        /// Total mass of rider plus bike in kilograms
        public var totalMass: Double = 75.0
        
        /// Functional Threshold Power in watts
        public var ftp: Double = 250.0
        
        /// Coefficient of drag × frontal area (m²)
        /// Typical values: 0.28-0.35 for road bikes
        public var cdA: Double = 0.32
        
        /// Coefficient of rolling resistance
        /// Typical values: 0.004 (road), 0.008 (gravel)
        public var crr: Double = 0.004
        
        /// Drivetrain efficiency (0.95-0.98 typical)
        public var drivetrainEfficiency: Double = 0.97
    }
    
    /// Bike configuration parameters
    public struct BikeConfiguration {
        /// Wheel circumference in meters
        /// 700x23C ≈ 2.096m, 700x25C ≈ 2.112m
        public var wheelCircumference: Double = 2.112
        
        /// Front chainring teeth counts (e.g., [50, 34] for compact)
        public var chainrings: [Int] = [50, 34]
        
        /// Rear cassette teeth counts
        public var cassette: [Int] = [11, 12, 13, 14, 16, 18, 20, 22, 25, 28, 32]
    }
    
    /// Cadence model parameters
    public struct CadenceModel {
        /// Target cadence range (RPM)
        public var lowCadenceTarget: Double = 75
        public var highCadenceTarget: Double = 95
        
        /// Power at 50% of cadence curve
        public var p50: Double = 250
        
        /// Slope of cadence-power relationship
        public var kP: Double = 75
        
        /// Maximum uphill cadence drop (RPM)
        public var maxUphillDrop: Double = 14
        
        /// Grade effect scaling factor
        public var gradeScale: Double = 6
        
        /// Downhill cadence bump (RPM)
        public var downhillBump: Double = 6
    }
    
    public var rider = RiderParameters()
    public var bike = BikeConfiguration()
    public var cadence = CadenceModel()
    
    public init() {}
}

/// Physics constants that should never change
public enum PhysicsConstants {
    /// Gravitational acceleration (m/s²)
    public static let gravity = 9.81
    
    /// Standard air density at sea level (kg/m³)
    public static let airDensity = 1.225
    
    /// Conversion factors
    public enum Conversion {
        /// Convert m/s to km/h
        public static let msToKmh = 3.6
        
        /// Convert m/s to mph
        public static let msToMph = 2.237
        
        /// Seconds per minute
        public static let secondsPerMinute = 60.0
        
        /// Degrees in full pedal revolution
        public static let degreesPerRevolution = 360.0
    }
}

/// Algorithm parameters with documentation
public enum AlgorithmParameters {
    /// Newton-Raphson solver parameters
    public enum NewtonRaphson {
        /// Convergence tolerance (relative error)
        public static let tolerance = 0.001
        
        /// Maximum iterations before giving up
        public static let maxIterations = 100
        
        /// Initial speed guess (m/s)
        public static let initialSpeed = 10.0
        
        /// Minimum speed bound (m/s)
        public static let minSpeed = 0.1
    }
    
    /// Time step constraints
    public enum TimeStep {
        /// Minimum time step (seconds)
        public static let minimum = 0.01
        
        /// Maximum time step (seconds)
        public static let maximum = 2.0
        
        /// Default control frequency (Hz)
        public static let controlFrequency = 4.0
        
        /// Default time step (seconds)
        public static let `default` = 0.25
    }
    
    /// Gear shifting parameters
    public enum GearShift {
        /// Cooldown time after rear shift (seconds)
        public static let rearCooldown = 2.0
        
        /// Cooldown time after front shift (seconds)
        public static let frontCooldown = 4.0
        
        /// Base shift rate (shifts per second)
        public static let baseRate = 1.0 / 60.0
        
        /// Error-based shift rate (shifts per second)
        public static let errorRate = 2.0 / 60.0
        
        /// Cadence error scaling factor
        public static let errorScale = 20.0
        
        /// Grade threshold for increased shifting (percent)
        public static let gradeThreshold = 5.0
    }
    
    /// Ornstein-Uhlenbeck noise model parameters
    public enum Noise {
        /// Mean reversion rate (1/s)
        public static let meanReversion = 2.0
        
        /// Noise standard deviation
        public static let standardDeviation = 0.6
        
        /// Variance allocation weights (must sum to 1.0)
        public static let microWeight = 0.50
        public static let macroWeight = 0.35
        public static let eventWeight = 0.15
        
        /// Time constants (seconds)
        public static let microTimeConstant = 0.167  // ~6 Hz variations
        public static let macroTimeConstant = 3.33   // ~0.3 Hz variations
    }
    
    /// Fatigue model parameters
    public enum Fatigue {
        /// Time constant for fatigue accumulation above FTP (seconds)
        public static let accumulationTime = 600.0
        
        /// Time constant for fatigue recovery below FTP (seconds)
        public static let recoveryTime = 300.0
    }
    
    /// Standing behavior parameters
    public enum Standing {
        /// Minimum grade to consider standing (percent)
        public static let gradeThreshold = 8.0
        
        /// Minimum power to consider standing (watts)
        public static let powerThreshold = 400.0
        
        /// Standing urgency probability
        public static let urgencyHigh = 0.3
        public static let urgencyLow = 0.05
        
        /// Minimum time between position changes (seconds)
        public static let positionChangeDelay = 3.0
        
        /// Standing exit rate (1/s)
        public static let exitRate = 0.1
        
        /// Cadence boost when standing (RPM)
        public static let cadenceBoost = 3.0
    }
}

/// BLE Protocol constants (defined by standards)
public enum BLEProtocol {
    /// FTMS protocol parameters
    public enum FTMS {
        /// Speed resolution (m/s)
        public static let speedUnit = 0.01
        
        /// Cadence resolution (RPM)
        public static let cadenceUnit = 0.5
        
        /// Update frequency (Hz)
        public static let updateFrequency = 4.0
    }
    
    /// Cycling Power Service parameters
    public enum CPS {
        /// Time resolution (seconds)
        public static let timeResolution = 1.0 / 1024.0
        
        /// Wheel revolution time resolution (seconds)
        public static let wheelTimeResolution = 1.0 / 2048.0
    }
    
    /// Running Speed and Cadence parameters
    public enum RSC {
        /// Speed resolution (m/s)
        public static let speedResolution = 1.0 / 256.0
        
        /// Update frequency (Hz)
        public static let updateFrequency = 2.0
    }
}

/// Validation limits for sanity checking
public enum ValidationLimits {
    /// Power limits (watts)
    public static let minPower = 0.0
    public static let maxPower = 2000.0
    public static let maxSimulationPower = 4000.0
    
    /// Speed limits (m/s)
    public static let minSpeed = 0.1
    public static let maxRealisticSpeed = 35.0  // 126 km/h
    public static let trackstandSpeed = 0.5      // 1.8 km/h
    
    /// Cadence limits (RPM)
    public static let minCadence = 0.0
    public static let maxCadence = 120.0
    public static let maxSprintCadence = 125.0
    
    /// Grade limits (percent)
    public static let minGrade = -30.0
    public static let maxGrade = 30.0
    
    /// Heart rate limits (BPM)
    public static let minHeartRate = 30.0
    public static let maxHeartRate = 220.0
}