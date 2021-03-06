//
//  OAPOIHelper.m
//  OsmAnd
//
//  Created by Alexey Kulish on 18/03/15.
//  Copyright (c) 2015 OsmAnd. All rights reserved.
//

#import "OAPOIHelper.h"
#import "OAPOI.h"
#import "OAPOIType.h"
#import "OAPOICategory.h"
#import "OAPOIFilter.h"
#import "OAPOIParser.h"
#import "OAPhrasesParser.h"
#import "OsmAndApp.h"
#import "OAAppSettings.h"

#include <OsmAndCore/CommonTypes.h>
#include <OsmAndCore/Data/DataCommonTypes.h>
#include <OsmAndCore/Data/ObfMapSectionInfo.h>
#include <OsmAndCore/Data/ObfPoiSectionInfo.h>
#include <OsmAndCore/FunctorQueryController.h>
#include <OsmAndCore/Utilities.h>
#include <OsmAndCore/Data/Amenity.h>
#include <OsmAndCore/Search/ISearch.h>
#include <OsmAndCore/Search/BaseSearch.h>
#include <OsmAndCore/Search/AmenitiesByNameSearch.h>
#include <OsmAndCore/Search/AmenitiesInAreaSearch.h>
#include <OsmAndCore/QKeyValueIterator.h>

#define kSearchLimitRaw 5000
#define kRadiusKmToMetersKoef 1200.0

@implementation OAPOIHelper {

    OsmAndAppInstance _app;
    int _limitCounter;
    BOOL _breakSearch;
    NSDictionary *_phrases;
    NSDictionary *_phrasesEN;

    double _radius;
    
    OsmAnd::AreaI _visibleArea;
    OsmAnd::ZoomLevel _zoomLevel;
    
    NSString *_prefLang;
}

+ (OAPOIHelper *)sharedInstance {
    static dispatch_once_t once;
    static OAPOIHelper * sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _app = [OsmAndApp instance];
        _searchLimit = kSearchLimitRaw;
        _isSearchDone = YES;
        [self readPOI];
        [self updateReferences];
        [self updatePhrases];
    }
    return self;
}

- (void)readPOI
{
    NSString *poiXmlPath = [[NSBundle mainBundle] pathForResource:@"poi_types" ofType:@"xml"];
    
    OAPOIParser *parser = [[OAPOIParser alloc] init];
    [parser getPOITypesSync:poiXmlPath];
    _poiTypes = parser.poiTypes;
    _poiCategories = parser.poiCategories;
    _poiFilters = parser.poiFilters;
}

- (void)updateReferences
{
    for (OAPOIType *p in _poiTypes)
    {
        if (p.reference)
        {
            OAPOIType *pType = [self getPoiTypeByName:p.name];
            if (pType)
            {
                p.tag = pType.tag;
                p.value = pType.value;
            }
        }
    }
}

- (OAPOIType *)getPoiTypeByName:(NSString *)name
{
    for (OAPOIType *p in _poiTypes)
        if ([p.name isEqualToString:name] && !p.reference)
            return p;

    return nil;
}

- (void)updatePhrases
{
    if (!_phrases)
    {
        NSString *lang = [[NSLocale preferredLanguages] firstObject];

        NSString *phrasesXmlPath = [[NSBundle mainBundle] pathForResource:@"phrases" ofType:@"xml" inDirectory:[NSString stringWithFormat:@"phrases/%@", lang]];

        if ([[NSFileManager defaultManager] fileExistsAtPath:phrasesXmlPath])
        {
            OAPhrasesParser *parser = [[OAPhrasesParser alloc] init];
            [parser getPhrasesSync:phrasesXmlPath];
            _phrases = parser.phrases;
        }
    }
    
    if (!_phrasesEN)
    {
        NSString *phrasesXmlPath = [[NSBundle mainBundle] pathForResource:@"phrases" ofType:@"xml" inDirectory:@"phrases/en"];
        
        OAPhrasesParser *parser = [[OAPhrasesParser alloc] init];
        [parser getPhrasesSync:phrasesXmlPath];
        _phrasesEN = parser.phrases;
    }

    if (_phrases.count > 0)
    {
        for (OAPOIType *poiType in _poiTypes)
        {
            poiType.nameLocalized = [self getPhrase:poiType.name];
            poiType.categoryLocalized = [self getPhrase:poiType.category];
            poiType.filterLocalized = [self getPhrase:poiType.filter];
        }
        for (OAPOICategory *c in _poiCategories.allKeys)
            c.nameLocalized = [self getPhrase:c.name];

        for (OAPOIFilter *f in _poiFilters.allKeys)
        {
            f.nameLocalized = [self getPhrase:f.name];
            f.categoryLocalized = [self getPhrase:f.category];
        }
    }
    
    if (_phrasesEN.count > 0)
    {
        for (OAPOIType *poiType in _poiTypes)
        {
            poiType.nameLocalizedEN = [self getPhraseEN:poiType.name];
            poiType.categoryLocalizedEN = [self getPhraseEN:poiType.category];
            poiType.filterLocalizedEN = [self getPhraseEN:poiType.filter];
            
            if (_phrases.count == 0)
            {
                poiType.nameLocalized = poiType.nameLocalizedEN;
                poiType.categoryLocalized = poiType.categoryLocalizedEN;
                poiType.filterLocalized = poiType.filterLocalizedEN;
            }
        }
        for (OAPOICategory *c in _poiCategories.allKeys)
        {
            c.nameLocalizedEN = [self getPhraseEN:c.name];
            if (_phrases.count == 0)
                c.nameLocalized = c.nameLocalizedEN;
        }
        
        for (OAPOIFilter *f in _poiFilters.allKeys)
        {
            f.nameLocalizedEN = [self getPhraseEN:f.name];
            f.categoryLocalizedEN = [self getPhraseEN:f.category];
            
            if (_phrases.count == 0)
            {
                f.nameLocalized = f.nameLocalizedEN;
                f.categoryLocalized = f.categoryLocalizedEN;
            }
        }
    }
}

-(NSString *)getPhrase:(NSString *)name 
{
    NSString *phrase = [_phrases objectForKey:[NSString stringWithFormat:@"poi_%@", name]];
    if (!phrase)
    {
        return [[name capitalizedString] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    }
    else
    {
        return phrase;
    }
}

-(NSString *)getPhraseEN:(NSString *)name
{
    NSString *phrase = [_phrasesEN objectForKey:[NSString stringWithFormat:@"poi_%@", name]];
    if (!phrase)
    {
        return [[name capitalizedString] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    }
    else
    {
        return phrase;
    }
}

- (NSArray *)poiTypesForCategory:(NSString *)categoryName
{
    for (OAPOICategory *c in _poiCategories.allKeys)
        if ([c.name isEqualToString:categoryName])
            return [_poiCategories objectForKey:c];

    return nil;
}

- (NSArray *)poiTypesForFilter:(NSString *)filterName
{
    for (OAPOIFilter *f in _poiFilters.allKeys)
        if ([f.name isEqualToString:filterName])
            return [_poiFilters objectForKey:f];
    
    return nil;
}

- (NSArray *)poiFiltersForCategory:(NSString *)categoryName
{
    NSMutableArray *res = [NSMutableArray array];
    for (OAPOIFilter *f in _poiFilters.allKeys)
        if ([f.category isEqualToString:categoryName])
            [res addObject:f];
    
    return [NSArray arrayWithArray:res];
}

- (OAPOIType *)getPoiType:(NSString *)tag value:(NSString *)value
{
    for (OAPOIType *t in _poiTypes)
        if ([t.tag isEqualToString:tag] && [t.value isEqualToString:value])
            return t;
    
    return nil;
}

- (OAPOIType *)getPoiTypeByCategory:(NSString *)category name:(NSString *)name
{
    for (OAPOIType *t in _poiTypes)
        if ([t.category isEqualToString:category] && [t.name isEqualToString:name])
            return t;
    
    return nil;
}

-(void)setVisibleScreenDimensions:(OsmAnd::AreaI)area zoomLevel:(OsmAnd::ZoomLevel)zoom
{
    _visibleArea = area;
    _zoomLevel = zoom;
}

-(void)findPOIsByKeyword:(NSString *)keyword
{
    int radius = -1;
    [self findPOIsByKeyword:keyword categoryName:nil poiTypeName:nil radiusIndex:&radius];
}

-(void)findPOIsByKeyword:(NSString *)keyword categoryName:(NSString *)categoryName poiTypeName:(NSString *)typeName radiusIndex:(int *)radiusIndex
{
    _isSearchDone = NO;
    _breakSearch = NO;
    if (*radiusIndex  < 0)
        _radius = 0.0;
    else
        _radius = kSearchRadiusKm[*radiusIndex] * kRadiusKmToMetersKoef;
    
    const auto& obfsCollection = _app.resourcesManager->obfsCollection;
    
    std::shared_ptr<const OsmAnd::IQueryController> ctrl;
    ctrl.reset(new OsmAnd::FunctorQueryController([self]
                                       (const OsmAnd::FunctorQueryController* const controller)
                                       {
                                           // should break?
                                           return (_radius == 0.0 && _limitCounter < 0) || _breakSearch;
                                       }));
    
    _limitCounter = _searchLimit;
    
    _prefLang = [[OAAppSettings sharedManager] settingPrefMapLanguage];
    
    if (_radius == 0.0) {
        
        const std::shared_ptr<OsmAnd::AmenitiesByNameSearch::Criteria>& searchCriteria = std::shared_ptr<OsmAnd::AmenitiesByNameSearch::Criteria>(new OsmAnd::AmenitiesByNameSearch::Criteria);
        
        searchCriteria->name = QString::fromNSString(keyword ? keyword : @"");
        searchCriteria->sourceFilter = ([self]
                                        (const std::shared_ptr<const OsmAnd::ObfInfo>& obfInfo)
                                        {
                                            return obfInfo->containsDataFor(&_visibleArea, OsmAnd::MinZoomLevel, OsmAnd::MaxZoomLevel, OsmAnd::ObfDataTypesMask().set(OsmAnd::ObfDataType::POI));
                                            
                                        });
        
        const auto search = std::shared_ptr<const OsmAnd::AmenitiesByNameSearch>(new OsmAnd::AmenitiesByNameSearch(obfsCollection));
        search->performSearch(*searchCriteria,
                              [self]
                              (const OsmAnd::ISearch::Criteria& criteria, const OsmAnd::ISearch::IResultEntry& resultEntry)
                              {
                                  [self onPOIFound:resultEntry];
                              },
                              ctrl);
    } else {
        
        const std::shared_ptr<OsmAnd::AmenitiesInAreaSearch::Criteria>& searchCriteria = std::shared_ptr<OsmAnd::AmenitiesInAreaSearch::Criteria>(new OsmAnd::AmenitiesInAreaSearch::Criteria);
        
        searchCriteria->sourceFilter = ([self]
                                        (const std::shared_ptr<const OsmAnd::ObfInfo>& obfInfo)
                                        {
                                            return true;
                                            //return obfInfo->containsDataFor(&_visibleArea, OsmAnd::MinZoomLevel, OsmAnd::MaxZoomLevel, OsmAnd::ObfDataTypesMask().set(OsmAnd::ObfDataType::POI));
                                            
                                        });
        
        auto categoriesFilter = QHash<QString, QStringList>();
        if (categoryName && typeName) {
            categoriesFilter.insert(QString::fromNSString(categoryName), QStringList(QString::fromNSString(typeName)));
        } else if (categoryName) {
            categoriesFilter.insert(QString::fromNSString(categoryName), QStringList());
        }
        searchCriteria->categoriesFilter = categoriesFilter;
        
        while (true)
        {
            searchCriteria->bbox31 = (OsmAnd::AreaI)OsmAnd::Utilities::boundingBox31FromAreaInMeters(_radius, _myLocation);
            
            const auto search = std::shared_ptr<const OsmAnd::AmenitiesInAreaSearch>(new OsmAnd::AmenitiesInAreaSearch(obfsCollection));
            search->performSearch(*searchCriteria,
                                  [self]
                                  (const OsmAnd::ISearch::Criteria& criteria, const OsmAnd::ISearch::IResultEntry& resultEntry)
                                  {
                                      [self onPOIFound:resultEntry];
                                  },
                                  ctrl);
            
            if (_limitCounter == _searchLimit && _radius < 12000.0)
            {
                *radiusIndex += 1;
                _radius = kSearchRadiusKm[*radiusIndex] * kRadiusKmToMetersKoef;
            }
            else
            {
                break;
            }
        }
    }
        
    _isSearchDone = YES;
    
    if (_delegate)
        [_delegate searchDone:_breakSearch];

}

-(BOOL)breakSearch
{
    _breakSearch = !_isSearchDone;
    return _breakSearch;
}

-(void)onPOIFound:(const OsmAnd::ISearch::IResultEntry&)resultEntry
{
    const auto amenity = ((OsmAnd::AmenitiesByNameSearch::ResultEntry&)resultEntry).amenity;
    OsmAnd::LatLon latLon = OsmAnd::Utilities::convert31ToLatLon(amenity->position31);
    
    OAPOI *poi = [[OAPOI alloc] init];
    poi.latitude = latLon.latitude;
    poi.longitude = latLon.longitude;
    poi.name = amenity->nativeName.toNSString();
    
    //NSLog(@">>> name=%@ id=%lld", amenity->nativeName.toNSString(), (uint64_t)amenity->id);

    NSMutableDictionary *names = [NSMutableDictionary dictionary];

    const QString lang = (_prefLang ? QString::fromNSString(_prefLang) : QString::null);
    for(const auto& entry : OsmAnd::rangeOf(amenity->localizedNames))
    {
        //NSLog(@"loc %@=%@", entry.key().toNSString(), entry.value().toNSString());
        if (lang != QString::null && entry.key() == lang)
            poi.nameLocalized = entry.value().toNSString();

        [names setObject:entry.value().toNSString() forKey:entry.key().toNSString()];
    }
    
    if (![names objectForKey:@""])
        [names setObject:poi.name forKey:@""];
    
    poi.localizedNames = [NSDictionary dictionaryWithDictionary:names];
    
    poi.distanceMeters = OsmAnd::Utilities::squareDistance31(_myLocation, amenity->position31);
    
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    
    NSString *descFieldLoc;
    if (_prefLang)
        descFieldLoc = [@"description:" stringByAppendingString:_prefLang];

    const auto& decodedValues = amenity->getDecodedValues();
    for(const auto& entry : decodedValues)
    {
        //NSLog(@"dec %@=%@", entry.key().toNSString(), (s.length > 50 ? [s substringToIndex:50] : s));

        if (entry.declaration->tagName.startsWith(QString("content")))
        {
            NSString *key = entry.declaration->tagName.toNSString();
            NSString *loc;
            if (key.length > 8)
                loc = [[key substringFromIndex:8] lowercaseString];
            else
                loc = @"";
            
            [content setObject:entry.value.toString().toNSString() forKey:loc];
        }

        
        // phone, website, description
        if (entry.declaration->tagName == QString("opening_hours"))
        {
            poi.hasOpeningHours = YES;
            poi.openingHours = entry.value.toString().toNSString();
        }
        
        if (_prefLang && !poi.nameLocalized)
        {
            const QString langTag = QString("name:").append(QString::fromNSString(_prefLang));
            if (entry.declaration->tagName == langTag)
                poi.nameLocalized = entry.value.toString().toNSString();
        }
        
        if (entry.declaration->tagName.startsWith(QString("description")) && !poi.desc)
            poi.desc = entry.value.toString().toNSString();
        if (descFieldLoc && entry.declaration->tagName == QString::fromNSString(descFieldLoc))
            poi.desc = entry.value.toString().toNSString();
    }
    
    poi.localizedContent = [NSDictionary dictionaryWithDictionary:content];
    
    if (!poi.nameLocalized)
        poi.nameLocalized = amenity->nativeName.toNSString();

    if (amenity->categories.isEmpty())
        return;
        
    const auto& catList = amenity->getDecodedCategories();
    if (catList.isEmpty())
        return;
    
    //NSLog(@"id=%ld poi.name=%@ lat=%f lon=%f", (long)(amenity->id), poi.name, poi.latitude, poi.longitude);
    
    NSString *category = catList.first().category.toNSString();
    NSString *subCategory = catList.first().subcategory.toNSString();
    
    OAPOIType *type = [self getPoiTypeByCategory:category name:subCategory];
    if (!type)
    {
        type = [[OAPOIType alloc] init];
        type.category = category;
        type.name = subCategory;
        type.nameLocalized = [self getPhrase:subCategory];
        type.nameLocalizedEN = [self getPhraseEN:subCategory];
    }
    poi.type = type;
    
    if (type.mapOnly)
        return;
    
    if (poi.name.length == 0)
        poi.name = type.name;
    if (poi.nameLocalized.length == 0)
        poi.nameLocalized = type.nameLocalized;
    
    _limitCounter--;
    
    if (_delegate)
        [_delegate poiFound:poi];
}

@end
