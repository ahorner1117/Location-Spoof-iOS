import CoreData

@objc(SavedLocation)
public class SavedLocation: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var address: String?
    @NSManaged public var createdAt: Date
}

extension SavedLocation {
    static func create(
        in context: NSManagedObjectContext,
        name: String,
        latitude: Double,
        longitude: Double,
        address: String? = nil
    ) -> SavedLocation {
        let location = SavedLocation(context: context)
        location.id = UUID()
        location.name = name
        location.latitude = latitude
        location.longitude = longitude
        location.address = address
        location.createdAt = Date()
        return location
    }

    static var fetchAllRequest: NSFetchRequest<SavedLocation> {
        let request = NSFetchRequest<SavedLocation>(entityName: "SavedLocation")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SavedLocation.createdAt, ascending: false)]
        return request
    }
}
